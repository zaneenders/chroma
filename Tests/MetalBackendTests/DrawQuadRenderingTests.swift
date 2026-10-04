import Chroma
import Foundation
import Metal
import Testing

@testable import MetalBackend

@Suite @MainActor
struct DrawQuadRenderingTests {
  @Test func texturedRoundedBorderUsesTheQuadPipeline() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let renderer = try MetalDisplayListRenderer(device: device, pixelFormat: .rgba8Unorm)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: 32, height: 32, mipmapped: false)
    descriptor.usage = .renderTarget
    descriptor.storageMode = .shared
    let target = try #require(device.makeTexture(descriptor: descriptor))
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    let image = try ImageResource(
      id: ImageID("red"), width: 1, height: 1,
      rgba8: Data([255, 0, 0, 255]))
    var list = DrawList()
    list.append(
      DrawQuad(
        rect: Rect(x: 4, y: 4, width: 24, height: 24),
        texture: .image(image), radii: CornerRadii(5), borderThickness: 4,
        edgeSoftness: 0.5))
    guard
      let frame = try renderer.prepareFrame(
        list, viewport: Size(width: 32, height: 32), rasterScale: Point(x: 1, y: 1),
        queue: queue, renderPass: pass)
    else {
      Issue.record("No frame slot available")
      return
    }
    #expect(frame.submit().waitUntilCompleted().succeeded)
    var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
    pixels.withUnsafeMutableBytes { bytes in
      unsafe target.getBytes(
        bytes.baseAddress!, bytesPerRow: 32 * 4,
        from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
    }
    func component(_ x: Int, _ y: Int, _ channel: Int) -> UInt8 { pixels[(y * 32 + x) * 4 + channel] }
    #expect(component(16, 6, 0) > 240)
    #expect(component(16, 6, 3) > 240)
    #expect(component(16, 16, 3) == 0)
    #expect(component(4, 4, 3) == 0)
    #expect(renderer.lastInstanceCount == 1)
    #expect(renderer.lastDrawCallCount == 1)
  }
}
