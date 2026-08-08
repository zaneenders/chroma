#if METAL_BACKEND

import AppKit
import Chroma
import MetalKit

@MainActor
public final class MetalRenderer: NSObject, MTKViewDelegate, NSWindowDelegate, Renderer {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let shapePipeline: MTLRenderPipelineState
  private let textPipeline: MTLRenderPipelineState
  private let fontAtlas: FontAtlas
  private let mtkView: ChromaInputView

  public let name = "Metal"

  package let interaction = Interaction()

  public var content: (any Block)?
  public var onClose: (() -> Void)?
  private var keyBindings: KeyBindings = .defaults {
    didSet { mtkView.keyBindings = keyBindings }
  }

  package func setKeyBindings(_ bindings: KeyBindings) {
    keyBindings = bindings
  }

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
    mtkView.isPaused = true
    mtkView.enableSetNeedsDisplay = true
    self.mtkView = mtkView

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: metalSource, options: nil)
    } catch {
      print("Shader compile failed:\n\(error)")
      return nil
    }

    guard
      let shapePipeline = Self.makePipeline(
        device: device,
        pixelFormat: mtkView.colorPixelFormat,
        library: library,
        vertex: "shape_vertex",
        fragment: "shape_fragment"
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
    self.shapePipeline = shapePipeline
    self.textPipeline = textPipeline

    super.init()
    mtkView.delegate = self
    mtkView.interaction = interaction
    mtkView.keyBindings = keyBindings
    Interaction.current = interaction
  }

  public convenience init?(size: Size) {
    self.init(frame: CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height)))
  }

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
    window.delegate = self
    window.center()
window.makeKeyAndOrderFront(nil)
    mtkView.needsDisplay = true
    window.makeFirstResponder(mtkView)

    app.activate(ignoringOtherApps: true)
    app.run()
  }

  public func windowWillClose(_ notification: Notification) {
    onClose?()
    NSApplication.shared.terminate(nil)
  }

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

  private var lastFrameTime: Double = 0
  private var smoothedFrameRate: Double = 0

  private var shapePool: [MTLBuffer] = []
  private var textPool: [MTLBuffer] = []
  private var poolBufferIndex = 0
  private let poolBufferCount = 3
  private var shapeInstances: [ShapeInstance] = []
  private var textInstances: [TextInstance] = []

  public func draw(in mtkView: MTKView) {
    guard
      let drawable = mtkView.currentDrawable,
      let rpd = mtkView.currentRenderPassDescriptor,
      let cmd = queue.makeCommandBuffer(),
      let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
    else {
      // The drawable may not be ready yet (e.g. before the view is attached to
      // a window). Retry next cycle so we don't stall on a blank view.
      mtkView.needsDisplay = true
      return
    }

    updateFrameRate()
    interaction.beginFrame(input: self.mtkView.frameInput())

    let viewport = Size(width: Float(mtkView.bounds.width), height: Float(mtkView.bounds.height))
    var drawList = DrawList()
    if let content {
      BlockEngine.draw(content, into: &drawList, in: Rect(origin: .zero, size: viewport), context: context)
    }
    interaction.endFrame()
    render(
      drawList,
      viewport: viewport,
      rasterScale: Point(
        x: Float(drawable.texture.width) / max(1, viewport.width),
        y: Float(drawable.texture.height) / max(1, viewport.height)),
      into: enc)

    enc.endEncoding()
    cmd.present(drawable)
    cmd.commit()

    poolBufferIndex = (poolBufferIndex + 1) % poolBufferCount
  }

  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    mtkView.needsDisplay = true
  }

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

  private enum Batch {
    case shape(instanceOffset: Int, instanceCount: Int)
    case text(instanceOffset: Int, instanceCount: Int)
    case pushClip(Rect)
    case popClip
  }

  private func render(
    _ drawList: DrawList,
    viewport: Size,
    rasterScale: Point,
    into enc: MTLRenderCommandEncoder
  ) {
    let metrics = FontMetrics()
    let pxToNDC = SIMD2<Float>(2 / viewport.width, 2 / viewport.height)
    func ndc(_ x: Float, _ y: Float) -> SIMD2<Float> {
      SIMD2(-1 + x * pxToNDC.x, 1 - y * pxToNDC.y)
    }

    shapeInstances.removeAll(keepingCapacity: true)
    textInstances.removeAll(keepingCapacity: true)
    var batches: [Batch] = []
    var shapeStart: Int?
    var textStart: Int?

    func closeShapes() {
      guard let start = shapeStart else { return }
      if shapeInstances.count > start {
        batches.append(.shape(instanceOffset: start, instanceCount: shapeInstances.count - start))
      }
      shapeStart = nil
    }

    func closeText() {
      guard let start = textStart else { return }
      if textInstances.count > start {
        batches.append(.text(instanceOffset: start, instanceCount: textInstances.count - start))
      }
      textStart = nil
    }

    func appendShape(_ rect: Rect, radii requestedRadii: CornerRadii, borderWidth: Float, color: Color) {
      guard rect.size.width > 0, rect.size.height > 0 else { return }
      let radii = requestedRadii.normalized(for: rect.size)
      // Give antialiasing room outside the logical bounds instead of clipping
      // coverage at the quad's edge.
      let edgePadding: Float = 1
      shapeInstances.append(
        ShapeInstance(
          dst_p0: ndc(rect.minX - edgePadding, rect.minY - edgePadding),
          dst_p1: ndc(rect.maxX + edgePadding, rect.maxY + edgePadding),
          size: [rect.size.width, rect.size.height],
          radii: [radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft],
          color: [color.r, color.g, color.b, color.a],
          borderWidth: max(0, borderWidth),
          padding: [edgePadding, 0, 0]))
    }

    var clipStack: [Rect] = []
    for command in drawList.commands {
      switch command {
      case .fillRect(let rect, let color):
        closeText()
        if shapeStart == nil { shapeStart = shapeInstances.count }
        appendShape(rect, radii: .zero, borderWidth: 0, color: color)
      case .strokeRect(let rect, let width, let color):
        closeText()
        if shapeStart == nil { shapeStart = shapeInstances.count }
        appendShape(rect, radii: .zero, borderWidth: width, color: color)
      case .fillRoundedRect(let rect, let radii, let color):
        closeText()
        if shapeStart == nil { shapeStart = shapeInstances.count }
        appendShape(rect, radii: radii, borderWidth: 0, color: color)
      case .strokeRoundedRect(let rect, let radii, let width, let color):
        closeText()
        if shapeStart == nil { shapeStart = shapeInstances.count }
        appendShape(rect, radii: radii, borderWidth: width, color: color)
      case .text(let position, let text, let color, let scale):
        closeShapes()
        if textStart == nil { textStart = textInstances.count }
        let glyphSize = SIMD2<Float>(metrics.glyphWidth, metrics.glyphHeight) * scale
        let advance = metrics.cellAdvance * scale
        var pen = SIMD2<Float>(position.x, position.y)
        for character in text {
          let byte = character.asciiValue ?? 0x20
          let (u0, v0, u1, v1) = fontAtlas.glyphUV(byte)
          textInstances.append(
            TextInstance(
              dst_p0: ndc(pen.x, pen.y),
              dst_p1: ndc(pen.x + glyphSize.x, pen.y + glyphSize.y),
              tex_tl: [u0, v0],
              tex_br: [u1, v1],
              color: [color.r, color.g, color.b, color.a]))
          pen.x += advance
        }
      case .pushClip(let rect):
        closeShapes()
        closeText()
        let clipped = clipStack.last.map { rect.intersection($0) ?? Rect.zero } ?? rect
        clipStack.append(clipped)
        batches.append(.pushClip(clipped))
      case .popClip:
        closeShapes()
        closeText()
        _ = clipStack.popLast()
        batches.append(.popClip)
      }
    }
    closeShapes()
    closeText()

    guard !batches.isEmpty else { return }
    let shapeBuffer = pooledBuffer(
      pool: &shapePool,
      byteCount: MemoryLayout<ShapeInstance>.stride * shapeInstances.count)
    if let shapeBuffer, !shapeInstances.isEmpty {
      shapeBuffer.contents().assumingMemoryBound(to: ShapeInstance.self)
        .update(from: shapeInstances, count: shapeInstances.count)
    }
    let textBuffer = pooledBuffer(
      pool: &textPool,
      byteCount: MemoryLayout<TextInstance>.stride * textInstances.count)
    if let textBuffer, !textInstances.isEmpty {
      textBuffer.contents().assumingMemoryBound(to: TextInstance.self)
        .update(from: textInstances, count: textInstances.count)
    }

    enc.setFragmentTexture(fontAtlas.texture, index: 0)
    var scissorStack: [Rect] = []
    let viewportRect = Rect(origin: .zero, size: viewport)

    for batch in batches {
      switch batch {
      case .shape(let instanceOffset, let instanceCount):
        guard let shapeBuffer else { continue }
        enc.setRenderPipelineState(shapePipeline)
        enc.setVertexBuffer(
          shapeBuffer,
          offset: instanceOffset * MemoryLayout<ShapeInstance>.stride,
          index: 0)
        enc.drawPrimitives(
          type: .triangleStrip,
          vertexStart: 0,
          vertexCount: 4,
          instanceCount: instanceCount)
      case .text(let instanceOffset, let instanceCount):
        guard let textBuffer else { continue }
        enc.setRenderPipelineState(textPipeline)
        enc.setVertexBuffer(
          textBuffer,
          offset: instanceOffset * MemoryLayout<TextInstance>.stride,
          index: 0)
        enc.drawPrimitives(
          type: .triangleStrip,
          vertexStart: 0,
          vertexCount: 4,
          instanceCount: instanceCount)
      case .pushClip(let rect):
        let current = scissorStack.last ?? viewportRect
        let clamped = current.intersection(rect) ?? Rect.zero
        scissorStack.append(clamped)
        enc.setScissorRect(clamped.asMtlScissor(scale: rasterScale))
      case .popClip:
        _ = scissorStack.popLast()
        enc.setScissorRect((scissorStack.last ?? viewportRect).asMtlScissor(scale: rasterScale))
      }
    }
  }

  private func pooledBuffer(pool: inout [MTLBuffer], byteCount: Int) -> MTLBuffer? {
    guard byteCount > 0 else { return nil }
    if pool.count <= poolBufferIndex {
      let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared)!
      pool.append(buffer)
      return buffer
    }
    let existing = pool[poolBufferIndex]
    if existing.length >= byteCount { return existing }
    let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared)!
    pool[poolBufferIndex] = buffer
    return buffer
  }

}

#elseif METAL_TRAIT
#error("The Metal backend requires macOS.")
#endif

#if METAL_BACKEND
import Metal

extension Rect {
  func asMtlScissor(scale: Point) -> MTLScissorRect {
    MTLScissorRect(
      x: Int((minX * scale.x).rounded(.down)),
      y: Int((minY * scale.y).rounded(.down)),
      width: Int((size.width * scale.x).rounded(.up)),
      height: Int((size.height * scale.y).rounded(.up))
    )
  }
}
#endif
