import MetalKit

struct Vertex {
  var positions: SIMD2<Float>
  var color: SIMD3<Float>
}

struct Uniforms {
  var modelMatrix: simd_float4x4
}

struct TextInstance {
  var dst_p0: SIMD2<Float>  // top-left in NDC
  var dst_p1: SIMD2<Float>  // bottom-right in NDC
  var tex_tl: SIMD2<Float>
  var tex_br: SIMD2<Float>
  var color: SIMD4<Float>
}

@MainActor
final class Renderer: NSObject, MTKViewDelegate {
  private let device: MTLDevice
  private let trianglePipeline: MTLRenderPipelineState
  private let textPipeline: MTLRenderPipelineState
  private let queue: MTLCommandQueue
  private let vertexBuffer: MTLBuffer
  private let uniformBuffer: MTLBuffer
  private let fontAtlas: FontAtlas

  var rotation: Float = 0
  var offsetX: Float = 0
  var offsetY: Float = 0

  init?(view: MTKView) {
    guard let device = view.device,
      let queue = device.makeCommandQueue()
    else {
      print("Unable to make command queue.")
      return nil
    }
    self.device = device
    self.queue = queue
    self.fontAtlas = FontAtlas(device: device)

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: metalSource, options: nil)
    } catch {
      print("Shader compile failed:\n\(error)")
      return nil
    }

    guard let triVert = library.makeFunction(name: "vertex_main"),
      let triFrag = library.makeFunction(name: "fragment_main")
    else {
      print("Triangle functions not found in library")
      return nil
    }

    let triDesc = MTLRenderPipelineDescriptor()
    triDesc.vertexFunction = triVert
    triDesc.fragmentFunction = triFrag
    triDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat

    do {
      self.trianglePipeline = try device.makeRenderPipelineState(descriptor: triDesc)
    } catch {
      print("Triangle pipeline creation failed:\n\(error)")
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

    let verties = [
      Vertex(positions: [0.0, 0.8], color: [1, 0, 0]),
      Vertex(positions: [-0.8, -0.8], color: [0, 1, 0]),
      Vertex(positions: [0.8, -0.8], color: [0, 0, 1]),
    ]
    guard
      let vertexBuffer = device.makeBuffer(
        bytes: verties,
        length: MemoryLayout<Vertex>.stride * verties.count,
        options: .storageModeShared)
    else {
      return nil
    }
    self.vertexBuffer = vertexBuffer

    guard
      let uniformBuffer = device.makeBuffer(
        length: MemoryLayout<Uniforms>.stride,
        options: .storageModeShared)
    else {
      return nil
    }
    self.uniformBuffer = uniformBuffer
  }

  func draw(in view: MTKView) {
    guard let drawable = view.currentDrawable,
      let rpd = view.currentRenderPassDescriptor,
      let cmd = queue.makeCommandBuffer()
    else { return }

    guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

    let cosA = cos(rotation)
    let sinA = sin(rotation)
    let rotate = simd_float4x4(rows: [
      [cosA, -sinA, 0, 0],
      [sinA, cosA, 0, 0],
      [0, 0, 1, 0],
      [0, 0, 0, 1],
    ])
    let translate = simd_float4x4(rows: [
      [1, 0, 0, offsetX],
      [0, 1, 0, offsetY],
      [0, 0, 1, 0],
      [0, 0, 0, 1],
    ])
    var uniforms = Uniforms(modelMatrix: translate * rotate)
    uniformBuffer.contents().copyMemory(
      from: &uniforms, byteCount: MemoryLayout<Uniforms>.stride)

    enc.setRenderPipelineState(trianglePipeline)
    enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    enc.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

    drawText(enc: enc, viewport: SIMD2<Float>(Float(drawable.texture.width), Float(drawable.texture.height)))

    enc.endEncoding()
    cmd.present(drawable)
    cmd.commit()
  }

  /// Draws a specimen containing every printable ASCII glyph (U+0020...U+007E).
  /// Keeping this in the demo makes malformed, missing, or inconsistently aligned glyphs obvious.
  private func drawText(enc: MTLRenderCommandEncoder, viewport: SIMD2<Float>) {
    let printableRows: [[UInt8]] = stride(from: 0x20, through: 0x70, by: 0x10).map { first in
      let last = min(first + 0x0f, 0x7e)
      let label = Array(String(format: "%02X  ", first).utf8)
      return label + (first...last).map(UInt8.init)
    }
    let lines = [Array("5x7 PRINTABLE ASCII 20-7E".utf8)] + printableRows

    // Use an integer scale so each font pixel lands on an exact block of screen pixels.
    let margin: Float = 20
    let longestLine = Float(lines.map(\.count).max() ?? 1)
    let widthScale = (viewport.x - margin * 2) / (longestLine * 6)
    let heightScale = (viewport.y - margin * 2) / (Float(lines.count) * 9)
    let scale = max(1, min(4, floor(min(widthScale, heightScale))))

    let pxToNDC = Float(2) / viewport
    let glyphSize = SIMD2<Float>(fontAtlas.glyphWidth, fontAtlas.glyphHeight) * scale
    let advance = SIMD2<Float>(fontAtlas.glyphWidth + fontAtlas.glyphSpacing, 9) * scale
    var instances = [TextInstance]()
    instances.reserveCapacity(lines.reduce(0) { $0 + $1.count })

    for (row, chars) in lines.enumerated() {
      let color: SIMD4<Float> = row == 0 ? [1, 0.78, 0.25, 1] : [1, 1, 1, 1]
      let top = SIMD2<Float>(margin, margin + Float(row) * advance.y)

      for (column, c) in chars.enumerated() {
        let pixelTopLeft = top + SIMD2<Float>(Float(column) * advance.x, 0)
        let pixelBottomRight = pixelTopLeft + glyphSize
        let ndcTopLeft = SIMD2<Float>(
          -1 + pixelTopLeft.x * pxToNDC.x,
          1 - pixelTopLeft.y * pxToNDC.y
        )
        let ndcBottomRight = SIMD2<Float>(
          -1 + pixelBottomRight.x * pxToNDC.x,
          1 - pixelBottomRight.y * pxToNDC.y
        )
        let (u0, v0, u1, v1) = fontAtlas.glyphUV(c)
        instances.append(
          TextInstance(
            dst_p0: ndcTopLeft,
            dst_p1: ndcBottomRight,
            tex_tl: [u0, v0],
            tex_br: [u1, v1],
            color: color
          ))
      }
    }

    guard
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

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
