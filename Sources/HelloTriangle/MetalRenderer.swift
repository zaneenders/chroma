import AppKit
import MetalKit

/// One glyph quad in the text instance buffer.
private struct TextInstance {
  var dst_p0: SIMD2<Float>  // top-left in NDC
  var dst_p1: SIMD2<Float>  // bottom-right in NDC
  var tex_tl: SIMD2<Float>  // font atlas UV of the glyph's top-left
  var tex_br: SIMD2<Float>  // font atlas UV of the glyph's bottom-right
  var color: SIMD4<Float>
}

/// The Metal backend.
///
/// Owns the view, all GPU state, and the conversion of backend-neutral draw
/// lists into encoded Metal commands. Everything above this type works in
/// pixel-space draw lists and never sees a Metal type.
@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let textPipeline: MTLRenderPipelineState
  private let fontAtlas: FontAtlas
  private let view: MTKView

  /// The view to install in a window, exposed opaquely so application code
  /// does not depend on MetalKit.
  var contentView: NSView { view }

  /// Produces the draw list for one frame. Called on every draw with the
  /// viewport size in pixels.
  var buildFrame: (inout DrawList, Size) -> Void = { _, _ in }

  init?(frame: CGRect) {
    guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue()
    else {
      print("Metal requires Apple Silicon or supported GPU.")
      return nil
    }
    self.device = device
    self.queue = queue
    self.fontAtlas = FontAtlas(device: device)

    let view = MTKView(frame: frame, device: device)
    view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
    self.view = view

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: metalSource, options: nil)
    } catch {
      print("Shader compile failed:\n\(error)")
      return nil
    }

    guard let textVert = library.makeFunction(name: "text_vertex"),
      let textFrag = library.makeFunction(name: "text_fragment")
    else {
      print("Text functions not found in library")
      return nil
    }

    let textDesc = MTLRenderPipelineDescriptor()
    textDesc.vertexFunction = textVert
    textDesc.fragmentFunction = textFrag
    textDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat

    // Enable alpha blending for text
    if let ca = textDesc.colorAttachments[0] {
      ca.isBlendingEnabled = true
      ca.sourceRGBBlendFactor = .sourceAlpha
      ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
      ca.rgbBlendOperation = .add
      ca.sourceAlphaBlendFactor = .one
      ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
      ca.alphaBlendOperation = .add
    }

    do {
      self.textPipeline = try device.makeRenderPipelineState(descriptor: textDesc)
    } catch {
      print("Text pipeline creation failed:\n\(error)")
      return nil
    }

    super.init()
    view.delegate = self
  }

  func draw(in view: MTKView) {
    guard let drawable = view.currentDrawable,
      let rpd = view.currentRenderPassDescriptor,
      let cmd = queue.makeCommandBuffer(),
      let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
    else { return }

    let viewport = Size(width: Float(drawable.texture.width), height: Float(drawable.texture.height))
    var drawList = DrawList()
    buildFrame(&drawList, viewport)
    render(drawList, viewport: viewport, into: enc)

    enc.endEncoding()
    cmd.present(drawable)
    cmd.commit()
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  /// Expands each text command into glyph instances and encodes one instanced draw.
  private func render(_ drawList: DrawList, viewport: Size, into enc: MTLRenderCommandEncoder) {
    let metrics = FontMetrics()
    let pxToNDC = SIMD2<Float>(2 / viewport.width, 2 / viewport.height)
    var instances = [TextInstance]()

    for command in drawList.commands {
      switch command {
      case let .text(position, text, color, scale):
        let glyphSize = SIMD2<Float>(metrics.glyphWidth, metrics.glyphHeight) * scale
        let advance = metrics.cellAdvance * scale
        var pen = SIMD2<Float>(position.x, position.y)
        for byte in text.utf8 {
          let ndcTopLeft = SIMD2<Float>(
            -1 + pen.x * pxToNDC.x,
            1 - pen.y * pxToNDC.y
          )
          let ndcBottomRight = SIMD2<Float>(
            -1 + (pen.x + glyphSize.x) * pxToNDC.x,
            1 - (pen.y + glyphSize.y) * pxToNDC.y
          )
          let (u0, v0, u1, v1) = fontAtlas.glyphUV(byte)
          instances.append(
            TextInstance(
              dst_p0: ndcTopLeft,
              dst_p1: ndcBottomRight,
              tex_tl: [u0, v0],
              tex_br: [u1, v1],
              color: [color.r, color.g, color.b, color.a]
            ))
          pen.x += advance
        }
      }
    }

    guard !instances.isEmpty,
      let buf = device.makeBuffer(
        bytes: instances,
        length: MemoryLayout<TextInstance>.stride * instances.count,
        options: .storageModeShared
      )
    else { return }

    enc.setRenderPipelineState(textPipeline)
    enc.setVertexBuffer(buf, offset: 0, index: 0)
    enc.setFragmentTexture(fontAtlas.texture, index: 0)
    enc.drawPrimitives(
      type: .triangleStrip,
      vertexStart: 0,
      vertexCount: 4,
      instanceCount: instances.count
    )
  }
}
