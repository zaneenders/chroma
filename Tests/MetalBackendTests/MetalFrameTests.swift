import Chroma
import Metal
import Testing

@testable import MetalBackend

@Suite @MainActor
struct MetalFrameTests {
  private func discard(_ frame: consuming MetalPreparedFrame) {}

  @Test func abandonedFramesReturnTheirSlots() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let renderer = try MetalDisplayListRenderer(device: device, pixelFormat: .rgba8Unorm)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: 8, height: 8, mipmapped: false)
    descriptor.usage = .renderTarget
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    func prepare() throws -> MetalPreparedFrame? {
      try renderer.prepareFrame(
        DrawList(), viewport: Size(width: 8, height: 8), rasterScale: Point(x: 1, y: 1),
        queue: queue, renderPass: pass)
    }
    guard let first = try prepare(), let second = try prepare(), let third = try prepare() else {
      Issue.record("Expected three available slots")
      return
    }
    if let unexpected = try prepare() {
      discard(unexpected)
      Issue.record("A fourth reservation must not be available")
    }
    discard(second)
    guard let replacement = try prepare() else {
      Issue.record("Abandoned reservation was not returned")
      return
    }
    discard(first)
    discard(third)
    let result = replacement.submit().waitUntilCompleted()
    #expect(result.succeeded)
    guard let recycled = try prepare() else {
      Issue.record("Completed reservation was not returned")
      return
    }
    discard(recycled)
  }

  @Test func droppedSubmissionDoesNotReleaseAnInFlightSlot() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let event = try #require(device.makeSharedEvent())
    let slots = MetalFrameSlots()
    let first = try #require(slots.acquire())
    let second = try #require(slots.acquire())
    let third = try #require(slots.acquire())
    let command = try #require(queue.makeCommandBuffer())
    command.encodeWaitForEvent(event, value: 1)
    defer { event.signaledValue = 1 }
    let prepared = MetalPreparedFrame(command: command, reservation: first)
    _ = prepared.submit()
    #expect(slots.acquire() == nil)
    event.signaledValue = 1
    command.waitUntilCompleted()
    #expect(command.status == .completed)
    let recycled = try #require(slots.acquire())
    #expect(recycled.index == first.index)
    first.release()
    #expect(slots.acquire() == nil)
    withExtendedLifetime((second, third, recycled)) {}
  }
}
