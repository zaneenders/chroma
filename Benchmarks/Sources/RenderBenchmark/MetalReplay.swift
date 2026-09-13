#if os(macOS)
import Chroma
import Metal
import MetalBackend

@MainActor
final class MetalReplay {
  let renderer: MetalDisplayListRenderer
  let queue: MTLCommandQueue
  let texture: MTLTexture
  let rasterScale: Point

  init(viewport: Size, rasterScale: Point = Point(x: 1, y: 1)) throws {
    self.rasterScale = rasterScale
    let width = viewport.width * rasterScale.x
    let height = viewport.height * rasterScale.y
    guard width.isFinite, height.isFinite, width >= 1, height >= 1,
      width <= 8192, height <= 8192
    else {
      throw BenchmarkError.failed("Unsupported capture raster dimensions (maximum 8192 per axis)")
    }
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw BenchmarkError.failed("Metal device/queue unavailable")
    }
    self.queue = queue
    renderer = try MetalDisplayListRenderer(device: device, pixelFormat: .rgba8Unorm)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: Int(width.rounded(.up)), height: Int(height.rounded(.up)), mipmapped: false)
    descriptor.usage = [.renderTarget]
    descriptor.storageMode = .private
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw BenchmarkError.failed("Offscreen texture unavailable")
    }
    self.texture = texture
  }

  /// Serial completion keeps replay measurements deterministic; frame leases
  /// independently prevent in-flight buffer reuse. CPU preparation includes
  /// command creation and encoding, but excludes submission/wait.
  func render(_ list: DrawList, viewport: Size) throws -> (cpu: Double, gpu: Double) {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    let start = now()
    guard let prepared = try renderer.prepareFrame(
      list, viewport: viewport, rasterScale: rasterScale, queue: queue, renderPass: pass)
    else { throw BenchmarkError.failed("No Metal frame slot available") }
    let cpu = now() - start
    let completion = prepared.submit().waitUntilCompleted()
    guard completion.succeeded else {
      throw BenchmarkError.failed("Metal execution failed: \(completion.errorDescription ?? "unknown error")")
    }
    return (cpu, completion.gpuDuration ?? 0)
  }
}
#endif
