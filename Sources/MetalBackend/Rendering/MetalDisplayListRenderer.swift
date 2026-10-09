import Chroma
import Metal

@MainActor
public final class MetalDisplayListRenderer {
  private let device: MTLDevice
  private let shapePipeline: MTLRenderPipelineState
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
  private var shapeInstances: [ShapeInstance] = []
  public private(set) var lastDrawCallCount = 0
  public private(set) var lastInstanceCount = 0
  private lazy var whiteTexture: MTLTexture? = {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    MetalUpload.replace(
      texture, bytes: [UInt8](repeating: 255, count: 4).span.bytes,
      width: 1, height: 1, bytesPerPixel: 4, level: 0)
    return texture
  }()

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

  private struct Batch {
    var offset: Int
    var count: Int
    var texture: MTLTexture
    var clip: Rect
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
    let pxToNDC = SIMD2<Float>(2 / viewport.width, 2 / viewport.height)
    func ndc(_ x: Float, _ y: Float) -> SIMD2<Float> {
      SIMD2(-1 + x * pxToNDC.x, 1 - y * pxToNDC.y)
    }
    func color(_ color: Color) -> SIMD4<Float> { [color.r, color.g, color.b, color.a] }
    imageFrame &+= 1
    shapeInstances.removeAll(keepingCapacity: true)
    var batches: [Batch] = []
    let root = Rect(origin: .zero, size: viewport)
    var clips: [Rect] = []
    for entry in drawList.culled(to: viewport).commands {
      switch entry {
      case .pushClip(let rect): clips.append((clips.last ?? root).intersection(rect) ?? .zero)
      case .popClip: _ = clips.popLast()
      case .quad(let quad):
        let rect = quad.rect
        guard rect.size.width > 0, rect.size.height > 0 else { continue }
        let texture: MTLTexture?
        switch quad.texture {
        case .white: texture = whiteTexture
        case .fontAtlas: texture = fontAtlas.texture
        case .image(let image): texture = imageTexture(for: image)
        }
        guard let texture else { continue }
        let radii = quad.radii.normalized(for: rect.size)
        let padding = max(1, quad.edgeSoftness)
        let uv = quad.sourceRect
        let clip = clips.last ?? root
        let offset = shapeInstances.count
        shapeInstances.append(
          ShapeInstance(
            dstP0: ndc(rect.minX - padding, rect.minY - padding),
            dstP1: ndc(rect.maxX + padding, rect.maxY + padding),
            size: [rect.size.width, rect.size.height],
            radii: [radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft],
            topLeft: color(quad.colors.topLeft), topRight: color(quad.colors.topRight),
            bottomRight: color(quad.colors.bottomRight), bottomLeft: color(quad.colors.bottomLeft),
            uv0: [uv.minX, uv.minY], uv1: [uv.maxX, uv.maxY],
            parameters: [
              max(0, quad.borderThickness), max(0, quad.edgeSoftness), padding,
              quad.texture == .fontAtlas ? 1 : 0,
            ]))
        if let last = batches.last, last.texture === texture, last.clip == clip {
          batches[batches.count - 1].count += 1
        } else {
          batches.append(Batch(offset: offset, count: 1, texture: texture, clip: clip))
        }
      }
    }
    evictImageTexturesIfNeeded()

    lastInstanceCount = shapeInstances.count
    guard
      let buffer = try pooledBuffer(
        pool: &shapePool, slot: slot,
        byteCount: MemoryLayout<ShapeInstance>.stride * shapeInstances.count)
    else { return }
    MetalUpload.copy(shapeInstances.span, to: buffer)
    enc.setRenderPipelineState(shapePipeline)
    for batch in batches {
      enc.setScissorRect(batch.clip.asMtlScissor(scale: rasterScale))
      enc.setFragmentTexture(batch.texture, index: 0)
      enc.setVertexBuffer(buffer, offset: batch.offset * MemoryLayout<ShapeInstance>.stride, index: 0)
      lastDrawCallCount += 1
      enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: batch.count)
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
