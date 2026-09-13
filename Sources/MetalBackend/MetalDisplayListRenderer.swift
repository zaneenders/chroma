import Chroma
import Metal

@MainActor
public final class MetalDisplayListRenderer {
  private let device: MTLDevice
  private let shapePipeline: MTLRenderPipelineState
  private let textPipeline: MTLRenderPipelineState
  private let imagePipeline: MTLRenderPipelineState
  private let fontAtlas: FontAtlas

  public init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
    self.device = device
    self.fontAtlas = try FontAtlas(device: device)

    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: metalSource, options: nil)
    } catch {
      throw BackendError.initializationFailed(
        backend: "Metal", stage: "shader library", reason: String(describing: error))
    }
    self.shapePipeline = try Self.makePipeline(
      device: device, pixelFormat: pixelFormat, library: library,
      vertex: "shape_vertex", fragment: "shape_fragment")
    self.textPipeline = try Self.makePipeline(
      device: device, pixelFormat: pixelFormat, library: library,
      vertex: "text_vertex", fragment: "text_fragment")
    self.imagePipeline = try Self.makePipeline(
      device: device, pixelFormat: pixelFormat, library: library,
      vertex: "text_vertex", fragment: "image_fragment")
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

  private let frameSlots = MetalFrameSlots()
  private var shapePool: [MTLBuffer?] = Array(repeating: nil, count: 3)
  private var textPool: [MTLBuffer?] = Array(repeating: nil, count: 3)
  private var shapeInstances: [ShapeInstance] = []
  private var textInstances: [TextInstance] = []
  public private(set) var lastDrawCallCount = 0
  public private(set) var lastInstanceCount = 0
  private var glyphRuns: [String: [SIMD4<Float>]] = [:]
  private var glyphRunOrder: [String] = []
  private var cachedGlyphCount = 0

  private func glyphRun(_ text: String) -> [SIMD4<Float>] {
    if let cached = glyphRuns[text] { return cached }
    let run = text.map { character in
      let (u0, v0, u1, v1) = fontAtlas.glyphUV(character)
      return SIMD4<Float>(u0, v0, u1, v1)
    }
    if run.count <= 65_536, text.utf8.count <= 65_536 {
      while !glyphRunOrder.isEmpty && (glyphRunOrder.count >= 1024 || cachedGlyphCount + run.count > 65_536) {
        let oldest = glyphRunOrder.removeFirst()
        cachedGlyphCount -= glyphRuns.removeValue(forKey: oldest)!.count
      }
      glyphRuns[text] = run
      glyphRunOrder.append(text)
      cachedGlyphCount += run.count
    }
    return run
  }

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

  private enum Batch {
    case shape(instanceOffset: Int, instanceCount: Int)
    case text(instanceOffset: Int, instanceCount: Int)
    case image(rect: Rect, clip: Rect, texture: MTLTexture)
    case pushClip(Rect)
    case popClip
  }

  public func prepareFrame(
    _ drawList: DrawList, viewport: Size, rasterScale: Point,
    queue: MTLCommandQueue, renderPass: MTLRenderPassDescriptor
  ) throws -> MetalPreparedFrame? {
    guard let reservation = frameSlots.acquire() else { return nil }
    guard queue.device === device,
      let command = queue.makeCommandBuffer(),
      let encoder = command.makeRenderCommandEncoder(descriptor: renderPass)
    else {
      throw BackendError.initializationFailed(
        backend: "Metal", stage: "frame", reason: "Command creation failed or queue uses a different device")
    }
    defer { encoder.endEncoding() }
    try encode(
      drawList, viewport: viewport, rasterScale: rasterScale, into: encoder,
      slot: reservation.index)
    return MetalPreparedFrame(command: command, reservation: reservation)
  }

  private func encode(
    _ drawList: DrawList,
    viewport: Size,
    rasterScale: Point,
    into enc: MTLRenderCommandEncoder,
    slot: Int
  ) throws {
    lastDrawCallCount = 0
    lastInstanceCount = 0
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
            instanceCount: textInstances.count - start))
      }
      textStart = nil
    }

    func appendShape(_ rect: Rect, radii requestedRadii: CornerRadii, borderWidth: Float, color: Color) {
      guard rect.size.width > 0, rect.size.height > 0 else { return }
      let radii = requestedRadii.normalized(for: rect.size)
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
    for command in drawList.culled(to: viewport).commands {
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
        let glyphSize = SIMD2<Float>(metrics.glyphWidth, metrics.glyphHeight) * scale
        let advance =
          metrics.cellAdvance * scale
        var pen = SIMD2<Float>(position.x, position.y)
        for uv in glyphRun(text) {
          if textStart == nil {
            textStart = textInstances.count
          }
          textInstances.append(
            TextInstance(
              dst_p0: ndc(pen.x, pen.y),
              dst_p1: ndc(pen.x + glyphSize.x, pen.y + glyphSize.y),
              tex_tl: [uv.x, uv.y],
              tex_br: [uv.z, uv.w],
              color: [color.r, color.g, color.b, color.a]))
          pen.x += advance
        }
      case .image(let destination, let image, let scaling, let alignment):
        closeShapes()
        closeText()
        guard
          let rect = scaling.drawRect(
            sourceSize: image.size, in: destination, alignment: alignment),
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

    lastInstanceCount = shapeInstances.count + textInstances.count
    guard !batches.isEmpty else { return }
    let shapeBuffer = try pooledBuffer(
      pool: &shapePool, slot: slot,
      byteCount: MemoryLayout<ShapeInstance>.stride * shapeInstances.count)
    if let shapeBuffer, !shapeInstances.isEmpty {
      MetalUpload.copy(shapeInstances, to: shapeBuffer)
    }
    let textBuffer = try pooledBuffer(
      pool: &textPool, slot: slot,
      byteCount: MemoryLayout<TextInstance>.stride * textInstances.count)
    if let textBuffer, !textInstances.isEmpty {
      MetalUpload.copy(textInstances, to: textBuffer)
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
        lastDrawCallCount += 1
        enc.drawPrimitives(
          type: .triangleStrip,
          vertexStart: 0,
          vertexCount: 4,
          instanceCount: instanceCount)
      case .text(let instanceOffset, let instanceCount):
        guard let textBuffer else { continue }
        enc.setRenderPipelineState(textPipeline)
        enc.setFragmentTexture(fontAtlas.texture, index: 0)
        enc.setVertexBuffer(
          textBuffer,
          offset: instanceOffset * MemoryLayout<TextInstance>.stride,
          index: 0)
        lastDrawCallCount += 1
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
        MetalUpload.setVertexValue(&instance, encoder: enc, index: 0)
        lastDrawCallCount += 1
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
    MetalUpload.replace(
      texture, bytes: image.rgba8.bytes, width: image.width, height: image.height,
      bytesPerPixel: 4, level: 0)
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

  private func pooledBuffer(pool: inout [MTLBuffer?], slot: Int, byteCount: Int) throws -> MTLBuffer? {
    guard byteCount > 0 else { return nil }
    if let existing = pool[slot], existing.length >= byteCount { return existing }
    guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
      throw BackendError.initializationFailed(
        backend: "Metal", stage: "frame buffer", reason: "Failed to allocate \(byteCount) bytes")
    }
    pool[slot] = buffer
    return buffer
  }
}
