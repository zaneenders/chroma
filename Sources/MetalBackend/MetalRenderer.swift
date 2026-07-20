#if METAL_BACKEND

import AppKit
import Chroma
import MetalKit

/// The Metal backend.
///
/// Owns the rendering surface, all GPU state, and the conversion of
/// backend-neutral draw lists into encoded Metal commands. Everything above
/// this type works in pixel-space draw lists and never sees a Metal type.
///
/// Use ``run(title:)`` for a standalone window, or embed ``contentView`` in
/// your own AppKit window to host the renderer inside an existing app.
@MainActor
public final class MetalRenderer: NSObject, MTKViewDelegate, Renderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let solidPipeline: MTLRenderPipelineState
  private let textPipeline: MTLRenderPipelineState
  private let fontAtlas: FontAtlas
  private let mtkView: ChromaInputView

  public let name = "Metal"

  /// The interaction context fed from AppKit input, installed as
  /// ``Interaction/current`` at initialization.
  public let interaction = Interaction()

  /// The content rendered every frame. Assign a new block at any time to swap
  /// content without touching the backend.
  public var content: (any Block)?

  /// The rendering surface to install in a window, exposed opaquely so
  /// application code does not depend on MetalKit. ``run(title:)`` installs
  /// this for you; embed it yourself to host the renderer in an existing app.
  public var contentView: NSView { mtkView }

  public init?(frame: CGRect) {
    guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue()
    else {
      print("Metal requires Apple Silicon or supported GPU.")
      return nil
    }
    self.device = device
    self.queue = queue
    self.fontAtlas = FontAtlas(device: device)

    let mtkView = ChromaInputView(frame: frame, device: device)
    mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
    self.mtkView = mtkView

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: metalSource, options: nil)
    } catch {
      print("Shader compile failed:\n\(error)")
      return nil
    }

    guard
      let solidPipeline = Self.makePipeline(
        device: device,
        pixelFormat: mtkView.colorPixelFormat,
        library: library,
        vertex: "solid_vertex",
        fragment: "solid_fragment"
      ),
      let textPipeline = Self.makePipeline(
        device: device,
        pixelFormat: mtkView.colorPixelFormat,
        library: library,
        vertex: "text_vertex",
        fragment: "text_fragment"
      )
    else {
      return nil
    }
    self.solidPipeline = solidPipeline
    self.textPipeline = textPipeline

    super.init()
    mtkView.delegate = self
    Interaction.current = interaction
  }

  /// Creates a renderer whose surface is `size` points across.
  public convenience init?(size: Size) {
    self.init(frame: CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height)))
  }

  /// Presents the renderer in its own window and runs the AppKit event loop.
  ///
  /// Owns all `NSApplication` setup and returns only when the app exits.
  public func run(title: String = "Hello Triangle") {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let window = NSWindow(
      contentRect: mtkView.frame,
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.contentView = mtkView
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.activate(ignoringOtherApps: true)
    app.run()
  }

  /// Creates an alpha-blended pipeline for the given shader functions.
  private static func makePipeline(
    device: MTLDevice,
    pixelFormat: MTLPixelFormat,
    library: MTLLibrary,
    vertex: String,
    fragment: String
  ) -> MTLRenderPipelineState? {
    guard let vertexFunction = library.makeFunction(name: vertex),
      let fragmentFunction = library.makeFunction(name: fragment)
    else {
      print("Shader functions \(vertex)/\(fragment) not found in library")
      return nil
    }

    let desc = MTLRenderPipelineDescriptor()
    desc.vertexFunction = vertexFunction
    desc.fragmentFunction = fragmentFunction
    desc.colorAttachments[0].pixelFormat = pixelFormat
    if let ca = desc.colorAttachments[0] {
      ca.isBlendingEnabled = true
      ca.sourceRGBBlendFactor = .sourceAlpha
      ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
      ca.rgbBlendOperation = .add
      ca.sourceAlphaBlendFactor = .one
      ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
      ca.alphaBlendOperation = .add
    }

    do {
      return try device.makeRenderPipelineState(descriptor: desc)
    } catch {
      print("Pipeline \(vertex)/\(fragment) creation failed:\n\(error)")
      return nil
    }
  }

  /// Frame timing for the smoothed ``Interaction/frameRate``.
  private var lastFrameTime: Double = 0
  private var smoothedFrameRate: Double = 0

  public func draw(in mtkView: MTKView) {
    guard let drawable = mtkView.currentDrawable,
      let rpd = mtkView.currentRenderPassDescriptor,
      let cmd = queue.makeCommandBuffer(),
      let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
    else { return }

    updateFrameRate()
    interaction.beginFrame(input: self.mtkView.frameInput())

    let viewport = Size(width: Float(drawable.texture.width), height: Float(drawable.texture.height))
    var drawList = DrawList()
    if let content {
      BlockEngine.draw(content, into: &drawList, in: Rect(origin: .zero, size: viewport))
    }
    render(drawList, viewport: viewport, into: enc)

    enc.endEncoding()
    cmd.present(drawable)
    cmd.commit()
  }

  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  /// Maintains an exponentially smoothed frame rate on the interaction
  /// context, for status displays.
  private func updateFrameRate() {
    let now = ProcessInfo.processInfo.systemUptime
    defer { lastFrameTime = now }
    guard lastFrameTime > 0 else { return }
    let delta = now - lastFrameTime
    guard delta > 0 else { return }
    let instant = 1 / delta
    smoothedFrameRate = smoothedFrameRate == 0 ? instant : smoothedFrameRate * 0.9 + instant * 0.1
    interaction.frameRate = smoothedFrameRate
  }

  /// A run of consecutive draw commands that share one render pipeline.
  ///
  /// Batches are encoded in draw-list order and commands are never reordered
  /// across pipelines: translucent GUI output depends on submission order.
  private enum Batch {
    case solid(indexOffset: Int, indexCount: Int)
    case text(instanceOffset: Int, instanceCount: Int)
    case pushClip(Rect)
    case popClip
  }

  /// Expands the draw list into shared geometry arrays, then encodes one draw
  /// per batch in draw-list order.
  private func render(_ drawList: DrawList, viewport: Size, into enc: MTLRenderCommandEncoder) {
    let metrics = FontMetrics()
    let pxToNDC = SIMD2<Float>(2 / viewport.width, 2 / viewport.height)
    func ndc(_ x: Float, _ y: Float) -> SIMD2<Float> {
      SIMD2(-1 + x * pxToNDC.x, 1 - y * pxToNDC.y)
    }

    var vertices = [GUIVertex]()
    var indices = [UInt32]()
    var instances = [TextInstance]()
    var batches: [Batch] = []

    // One open batch per pipeline; consecutive same-pipeline commands merge
    // into the open batch, and a command for the other pipeline closes it.
    var solidStart: Int?
    var textStart: Int?

    func closeSolid() {
      guard let start = solidStart else { return }
      if indices.count > start {
        batches.append(.solid(indexOffset: start, indexCount: indices.count - start))
      }
      solidStart = nil
    }

    func closeText() {
      guard let start = textStart else { return }
      if instances.count > start {
        batches.append(.text(instanceOffset: start, instanceCount: instances.count - start))
      }
      textStart = nil
    }

    func appendQuad(_ rect: Rect, color: Color) {
      guard rect.size.width > 0, rect.size.height > 0 else { return }
      let base = UInt32(vertices.count)
      let c = SIMD4(color.r, color.g, color.b, color.a)
      vertices.append(GUIVertex(position: ndc(rect.minX, rect.minY), uv: .zero, color: c))
      vertices.append(GUIVertex(position: ndc(rect.maxX, rect.minY), uv: .zero, color: c))
      vertices.append(GUIVertex(position: ndc(rect.minX, rect.maxY), uv: .zero, color: c))
      vertices.append(GUIVertex(position: ndc(rect.maxX, rect.maxY), uv: .zero, color: c))
      indices.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 1, base + 3])
    }

    /// Expands a stroked rectangle into four solid edge quads.
    func appendStroke(_ rect: Rect, width: Float, color: Color) {
      let border = max(0, width)
      guard border > 0, rect.size.width > 0, rect.size.height > 0 else { return }
      guard rect.size.width > 2 * border, rect.size.height > 2 * border else {
        // The border covers the whole rect; fill it instead of inverting edges.
        appendQuad(rect, color: color)
        return
      }
      let (x, y) = (rect.origin.x, rect.origin.y)
      let (w, h) = (rect.size.width, rect.size.height)
      appendQuad(Rect(origin: Point(x: x, y: y), size: Size(width: w, height: border)), color: color)
      appendQuad(Rect(origin: Point(x: x, y: y + h - border), size: Size(width: w, height: border)), color: color)
      appendQuad(
        Rect(origin: Point(x: x, y: y + border), size: Size(width: border, height: h - 2 * border)),
        color: color
      )
      appendQuad(
        Rect(origin: Point(x: x + w - border, y: y + border), size: Size(width: border, height: h - 2 * border)),
        color: color
      )
    }

    /// Clip stack of pixel-space rects. The current clip is the top element
    /// (or the full viewport when empty).
    var clipStack: [Rect] = []

    for command in drawList.commands {
      switch command {
      case .fillRect(let rect, let color):
        closeText()
        if solidStart == nil { solidStart = indices.count }
        appendQuad(rect, color: color)
      case .strokeRect(let rect, let width, let color):
        closeText()
        if solidStart == nil { solidStart = indices.count }
        appendStroke(rect, width: width, color: color)
      case .text(let position, let text, let color, let scale):
        closeSolid()
        if textStart == nil { textStart = instances.count }
        let glyphSize = SIMD2<Float>(metrics.glyphWidth, metrics.glyphHeight) * scale
        let advance = metrics.cellAdvance * scale
        var pen = SIMD2<Float>(position.x, position.y)
        for byte in text.utf8 {
          let (u0, v0, u1, v1) = fontAtlas.glyphUV(byte)
          instances.append(
            TextInstance(
              dst_p0: ndc(pen.x, pen.y),
              dst_p1: ndc(pen.x + glyphSize.x, pen.y + glyphSize.y),
              tex_tl: [u0, v0],
              tex_br: [u1, v1],
              color: [color.r, color.g, color.b, color.a]
            ))
          pen.x += advance
        }
      case .pushClip(let rect):
        closeSolid()
        closeText()
        let clipped = clipStack.last.map { rect.intersection($0) ?? Rect.zero } ?? rect
        clipStack.append(clipped)
        batches.append(.pushClip(clipped))
      case .popClip:
        closeSolid()
        closeText()
        _ = clipStack.popLast()
        batches.append(.popClip)
      }
    }
    closeSolid()
    closeText()

    guard !batches.isEmpty else { return }

    // Per-frame scratch buffers. Buffer reuse and growth are a separate step;
    // the batch offsets below are structured so only this allocation changes.
    let vertexBuffer: MTLBuffer?
    let indexBuffer: MTLBuffer?
    if vertices.isEmpty {
      vertexBuffer = nil
      indexBuffer = nil
    } else {
      vertexBuffer = device.makeBuffer(
        bytes: vertices,
        length: MemoryLayout<GUIVertex>.stride * vertices.count,
        options: .storageModeShared
      )
      indexBuffer = device.makeBuffer(
        bytes: indices,
        length: MemoryLayout<UInt32>.stride * indices.count,
        options: .storageModeShared
      )
    }
    let textBuffer: MTLBuffer?
    if instances.isEmpty {
      textBuffer = nil
    } else {
      textBuffer = device.makeBuffer(
        bytes: instances,
        length: MemoryLayout<TextInstance>.stride * instances.count,
        options: .storageModeShared
      )
    }

    enc.setFragmentTexture(fontAtlas.texture, index: 0)

    /// Pixel-space scissor stack applied during encoding. Pop restores the
    /// previous scissor; when the stack is empty the scissor is disabled.
    var scissorStack: [Rect] = []
    let viewportRect = Rect(origin: .zero, size: viewport)

    for batch in batches {
      switch batch {
      case .solid(let indexOffset, let indexCount):
        guard let vertexBuffer, let indexBuffer else { continue }
        enc.setRenderPipelineState(solidPipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.drawIndexedPrimitives(
          type: .triangle,
          indexCount: indexCount,
          indexType: .uint32,
          indexBuffer: indexBuffer,
          indexBufferOffset: indexOffset * MemoryLayout<UInt32>.stride
        )
      case .text(let instanceOffset, let instanceCount):
        guard let textBuffer else { continue }
        enc.setRenderPipelineState(textPipeline)
        enc.setVertexBuffer(
          textBuffer,
          offset: instanceOffset * MemoryLayout<TextInstance>.stride,
          index: 0
        )
        enc.drawPrimitives(
          type: .triangleStrip,
          vertexStart: 0,
          vertexCount: 4,
          instanceCount: instanceCount
        )
      case .pushClip(let rect):
        let current = scissorStack.last ?? viewportRect
        let clamped = current.intersection(rect) ?? Rect.zero
        scissorStack.append(clamped)
        enc.setScissorRect(clamped.asMtlScissor)
      case .popClip:
        _ = scissorStack.popLast()
        if let prev = scissorStack.last {
          enc.setScissorRect(prev.asMtlScissor)
        } else {
          enc.setScissorRect(viewportRect.asMtlScissor)
        }
      }
    }
  }
}

#elseif METAL_TRAIT
#error("The Metal backend requires macOS.")
#endif

#if METAL_BACKEND
import Metal

extension Rect {
  /// Converts a pixel-space `Rect` into a `MTLScissorRect` for the
  /// render-command encoder. Metal scissor uses the same top-left origin.
  var asMtlScissor: MTLScissorRect {
    MTLScissorRect(
      x: Int(minX.rounded(.down)),
      y: Int(minY.rounded(.down)),
      width: Int(size.width.rounded(.up)),
      height: Int(size.height.rounded(.up))
    )
  }
}
#endif
