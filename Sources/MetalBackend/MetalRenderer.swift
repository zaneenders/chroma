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
  private let imagePipeline: MTLRenderPipelineState
  private let fontAtlas: FontAtlas
  private let mtkView: ChromaInputView

  public let name = "Metal"

  package let interaction = Interaction()

  public var content: (any Block)?
  public var onClose: (() -> Void)?
  private var keyBindings = KeyBindings() {
    didSet { mtkView.keyBindings = keyBindings }
  }
  private var minimumRefreshRate: Double = 0
  private var refreshTimer: Timer?

  package func setKeyBindings(_ bindings: KeyBindings) {
    keyBindings = bindings
  }

  package func setMinimumRefreshRate(_ refreshRate: Double) {
    minimumRefreshRate = refreshRate.isFinite ? max(0, refreshRate) : 0
    updateRefreshTimer()
  }

  public var contentView: NSView { mtkView }

  public init(frame: CGRect) throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw BackendError.unavailable(
        backend: "Metal",
        reason: "no compatible GPU was found"
      )
    }
    guard let queue = device.makeCommandQueue() else {
      throw BackendError.initializationFailed(
        backend: "Metal",
        stage: "command queue",
        reason: "the device could not create a command queue"
      )
    }
    self.device = device
    self.queue = queue
    self.fontAtlas = try FontAtlas(device: device)

    let mtkView = ChromaInputView(frame: frame, device: device)
    mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
    mtkView.isPaused = true
    mtkView.enableSetNeedsDisplay = true
    self.mtkView = mtkView

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: metalSource, options: nil)
    } catch {
      throw BackendError.initializationFailed(
        backend: "Metal",
        stage: "shader library",
        reason: String(describing: error)
      )
    }

    let shapePipeline = try Self.makePipeline(
      device: device,
      pixelFormat: mtkView.colorPixelFormat,
      library: library,
      vertex: "shape_vertex",
      fragment: "shape_fragment"
    )
    let textPipeline = try Self.makePipeline(
      device: device,
      pixelFormat: mtkView.colorPixelFormat,
      library: library,
      vertex: "text_vertex",
      fragment: "text_fragment"
    )
    let imagePipeline = try Self.makePipeline(
      device: device,
      pixelFormat: mtkView.colorPixelFormat,
      library: library,
      vertex: "text_vertex",
      fragment: "image_fragment"
    )
    self.shapePipeline = shapePipeline
    self.textPipeline = textPipeline
    self.imagePipeline = imagePipeline

    super.init()
    mtkView.delegate = self
    mtkView.interaction = interaction
    mtkView.keyBindings = keyBindings
    interaction.onRedrawRequested = { [weak mtkView] in
      mtkView?.needsDisplay = true
    }
  }

  public convenience init(size: Size) throws {
    try self.init(frame: CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height)))
  }

  private func updateRefreshTimer() {
    refreshTimer?.invalidate()
    refreshTimer = nil
    guard minimumRefreshRate > 0 else { return }

    let timer = Timer(timeInterval: 1 / minimumRefreshRate, repeats: true) { [weak mtkView] _ in
      MainActor.assumeIsolated {
        mtkView?.needsDisplay = true
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    refreshTimer = timer
  }

  public func run(title: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let window = NSWindow(
      contentRect: mtkView.frame,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.collectionBehavior.insert(.fullScreenPrimary)
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
  ) throws -> MTLRenderPipelineState {
    guard let vertexFunction = library.makeFunction(name: vertex),
      let fragmentFunction = library.makeFunction(name: fragment)
    else {
      throw BackendError.initializationFailed(
        backend: "Metal",
        stage: "render pipeline",
        reason: "shader functions \(vertex)/\(fragment) were not found"
      )
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
      throw BackendError.initializationFailed(
        backend: "Metal",
        stage: "render pipeline \(vertex)/\(fragment)",
        reason: String(describing: error)
      )
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

  private struct CachedImageTexture {
    var generation: UInt64
    var width: Int
    var height: Int
    var texture: MTLTexture
    var byteCount: Int
    var lastUsedFrame: UInt64
  }
  private var imageTextures: [ImageID: CachedImageTexture] = [:]
  private var imageTextureBytes = 0
  private var imageFrame: UInt64 = 0
  private let maximumImageTextureCount = 128
  private let maximumImageTextureBytes = 256 * 1024 * 1024

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
    let redrawRequested = interaction.consumeRedrawRequest()
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

    if redrawRequested {
      mtkView.needsDisplay = true
    }
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
    case text(instanceOffset: Int, instanceCount: Int, face: FontFace)
    case image(rect: Rect, clip: Rect, texture: MTLTexture)
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

    imageFrame &+= 1
    shapeInstances.removeAll(keepingCapacity: true)
    textInstances.removeAll(keepingCapacity: true)
    var batches: [Batch] = []
    var shapeStart: Int?
    var textStart: Int?
    var textFace: FontFace?

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
        batches.append(
          .text(
            instanceOffset: start,
            instanceCount: textInstances.count - start,
            face: textFace ?? .readable))
      }
      textStart = nil
      textFace = nil
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
      case .text(let position, let text, let color, let scale, let face):
        closeShapes()
        let glyphSize = SIMD2<Float>(metrics.glyphWidth, metrics.glyphHeight) * scale
        let advance =
          (face == .readable ? metrics.cellAdvance : metrics.displayCellAdvance) * scale
        var pen = SIMD2<Float>(position.x, position.y)
        for character in text {
          if textFace != nil, textFace != face { closeText() }
          if textStart == nil {
            textStart = textInstances.count
            textFace = face
          }
          let (u0, v0, u1, v1) = fontAtlas.glyphUV(character, readable: face == .readable)
          textInstances.append(
            TextInstance(
              dst_p0: ndc(pen.x, pen.y),
              dst_p1: ndc(pen.x + glyphSize.x, pen.y + glyphSize.y),
              tex_tl: [u0, v0],
              tex_br: [u1, v1],
              color: [color.r, color.g, color.b, color.a]))
          pen.x += advance
        }
      case .image(let destination, let image, let contentMode):
        closeShapes()
        closeText()
        guard
          let rect = contentMode.drawRect(sourceSize: image.size, in: destination),
          let texture = imageTexture(for: image)
        else { continue }
        let viewportRect = Rect(origin: .zero, size: viewport)
        let activeClip = clipStack.last.map { $0.intersection(viewportRect) ?? .zero } ?? viewportRect
        guard let clip = activeClip.intersection(destination) else { continue }
        batches.append(.image(rect: rect, clip: clip, texture: texture))
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
    evictImageTexturesIfNeeded()

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
      case .text(let instanceOffset, let instanceCount, _):
        guard let textBuffer else { continue }
        enc.setRenderPipelineState(textPipeline)
        enc.setFragmentTexture(fontAtlas.texture, index: 0)
        enc.setVertexBuffer(
          textBuffer,
          offset: instanceOffset * MemoryLayout<TextInstance>.stride,
          index: 0)
        enc.drawPrimitives(
          type: .triangleStrip,
          vertexStart: 0,
          vertexCount: 4,
          instanceCount: instanceCount)
      case .image(let rect, let clip, let texture):
        var instance = TextInstance(
          dst_p0: ndc(rect.minX, rect.minY),
          dst_p1: ndc(rect.maxX, rect.maxY),
          tex_tl: [0, 0], tex_br: [1, 1], color: [1, 1, 1, 1])
        enc.setScissorRect(clip.asMtlScissor(scale: rasterScale))
        enc.setRenderPipelineState(imagePipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setVertexBytes(&instance, length: MemoryLayout<TextInstance>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.setScissorRect((scissorStack.last ?? viewportRect).asMtlScissor(scale: rasterScale))
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

  private func imageTexture(for image: Chroma.ImageResource) -> MTLTexture? {
    if var cached = imageTextures[image.id],
      cached.generation == image.generation,
      cached.width == image.width,
      cached.height == image.height
    {
      cached.lastUsedFrame = imageFrame
      imageTextures[image.id] = cached
      return cached.texture
    }

    if let stale = imageTextures.removeValue(forKey: image.id) {
      imageTextureBytes -= stale.byteCount
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: image.width, height: image.height, mipmapped: false)
    descriptor.usage = .shaderRead
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    image.rgba8.withUnsafeBytes { bytes in
      texture.replace(
        region: MTLRegionMake2D(0, 0, image.width, image.height),
        mipmapLevel: 0,
        withBytes: bytes.baseAddress!,
        bytesPerRow: image.width * 4)
    }
    let byteCount = image.width * image.height * 4
    imageTextures[image.id] = CachedImageTexture(
      generation: image.generation, width: image.width, height: image.height,
      texture: texture, byteCount: byteCount, lastUsedFrame: imageFrame)
    imageTextureBytes += byteCount
    return texture
  }

  private func evictImageTexturesIfNeeded() {
    while imageTextures.count > maximumImageTextureCount
      || imageTextureBytes > maximumImageTextureBytes
    {
      guard let oldest = imageTextures.min(by: { $0.value.lastUsedFrame < $1.value.lastUsedFrame }) else {
        break
      }
      imageTextureBytes -= oldest.value.byteCount
      imageTextures.removeValue(forKey: oldest.key)
    }
  }

  private func pooledBuffer(pool: inout [MTLBuffer], byteCount: Int) -> MTLBuffer? {
    guard byteCount > 0 else { return nil }
    if pool.count <= poolBufferIndex {
      guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
        return nil
      }
      pool.append(buffer)
      return buffer
    }
    let existing = pool[poolBufferIndex]
    if existing.length >= byteCount { return existing }
    guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
      return nil
    }
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
