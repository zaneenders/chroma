import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct LayoutBufferTests {
  private let viewport = Rect(x: 0, y: 0, width: 120, height: 80)

  @Test func commonRecordsDoNotInlineRareControlPayloads() {
    #expect(MemoryLayout<LayoutBuffer.Record>.stride <= 128)
    #expect(MemoryLayout<LayoutContext>.stride <= 96)
  }

  @Test func resetAndDifferentOwnersRejectRecycledHandles() {
    var first = LayoutBuffer()
    var second = LayoutBuffer()
    let context = LayoutContext()
    let old = first.color(.white, context: context)
    #expect(first.contains(old) == true)
    #expect(second.contains(old) == false)
    let capacity = first.capacity
    first.reset()
    let replacement = first.color(.black, context: context)
    #expect(first.capacity == capacity)
    #expect(first.contains(old) == false)
    #expect(first.contains(replacement) == true)
    #expect(old != replacement)
    second.reset()
    #expect(second.contains(replacement) == false)
  }

  @Test func directRootKeepsOrderedCommandsAcrossFreshOperations() {
    let build: LayoutBuilder = { buffer, context in
      let first = buffer.text(Text("first"), context: context.keyed("first"))
      let second = buffer.text(Text("second"), context: context.keyed("second"))
      return buffer.stack([first, second], axis: .vertical, spacing: 3, context: context)
    }
    let host = HeadlessHost(size: viewport.size)
    defer { host.close() }
    host.build = build
    let first = host.render()
    #expect(host.render().commands == first.commands)
    #expect(
      first.paintSnapshot.compactMap { if case .text(_, let text, _, _) = $0 { text } else { nil } } == [
        "first", "second",
      ])
  }

  @Test func warmedTypedStorageGrowsOnlyWhenWorkloadGrows() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    var buffer = LayoutBuffer()
    let context = LayoutContext()
    let build: LayoutBuilder = { buffer, context in
      let first = buffer.text(Text("first"), context: context.childScope(0))
      let second = buffer.text(Text("second"), context: context.childScope(1))
      let spacer = buffer.spacer(context: context.childScope(2))
      return buffer.stack([first, second, spacer], axis: .vertical, context: context)
    }
    for iteration in 0..<20 {
      PipelineMetrics.reset()
      let root = build(&buffer, context)
      #expect(buffer.count == 4)
      _ = buffer.sizeThatFits(root, viewport.size)
      beginTestFrame(context.interaction, input: InputState())
      buffer.register(root, in: viewport)
      var list = DrawList()
      buffer.paint(root, into: &list, in: viewport)
      context.interaction.endFrame()
      #expect(PipelineMetrics.snapshot.layoutNodes == 4)
      if iteration > 0 {
        #expect(PipelineMetrics.snapshot.bufferGrowths == 0)
        #expect(PipelineMetrics.snapshot.textLayouts == 0)
      }
      buffer.reset()
      #expect(buffer.count == 0)
    }
  }

  @Test func cachedStackGeometryIsRelativeToItsCurrentOrigin() {
    var buffer = LayoutBuffer()
    let context = LayoutContext()
    var ignored = context
    ignored.navigationIgnored = true
    let firstText = buffer.text(Text("A"), context: ignored.childScope(0))
    let secondText = buffer.text(Text("B"), context: ignored.childScope(1))
    let root = buffer.stack([firstText, secondText], axis: .vertical, spacing: 2, context: ignored)
    beginTestFrame(context.interaction, input: InputState())
    buffer.register(root, in: viewport)
    var first = DrawList()
    buffer.paint(root, into: &first, in: viewport)
    context.interaction.endFrame()
    let shifted = Rect(x: 30, y: 40, width: viewport.size.width, height: viewport.size.height)
    beginTestFrame(context.interaction, input: InputState())
    buffer.register(root, in: shifted)
    var second = DrawList()
    buffer.paint(root, into: &second, in: shifted)
    context.interaction.endFrame()
    let old = first.commands.compactMap { if case .quad(let q) = $0 { q.rect } else { nil } }
    let new = second.commands.compactMap { if case .quad(let q) = $0 { q.rect } else { nil } }
    #expect(zip(old, new).allSatisfy { $1.minX == $0.minX + 30 && $1.minY == $0.minY + 40 })
    buffer.reset()
    #expect(first.commands.count == second.commands.count)
    #expect(first.commands != second.commands)
  }

  @Test func resetReleasesCustomCallbackCapturesWithoutDiscardingCapacity() {
    final class Capture {}
    var capture: Capture? = Capture()
    weak let weakCapture = capture
    var buffer = LayoutBuffer()
    _ = buffer.customLeaf(
      context: LayoutContext(),
      measure: { [capture = capture!] proposal in
        withExtendedLifetime(capture) {}
        return proposal
      }, register: { _ in }, paint: { _, _ in })
    capture = nil
    #expect(weakCapture != nil)
    let capacity = buffer.capacity
    buffer.reset()
    #expect(weakCapture == nil)
    #expect(buffer.capacity == capacity)
    buffer.reset(releasingCapacity: true)
    #expect(buffer.capacity == 0)
  }

  @Test func callbacksCanGrowStorageDuringRegistration() {
    var buffer = LayoutBuffer()
    var context = LayoutContext()
    context.navigationIgnored = true
    let root = buffer.interactive(
      action: {},
      content: { buffer, context, _ in
        let rows = (0..<200).map { buffer.text(Text("abc"), context: context.keyed($0)) }
        return buffer.stack(rows, axis: .vertical, context: context)
      }, context: context)
    beginTestFrame(context.interaction, input: InputState())
    buffer.register(root, in: viewport)
    context.interaction.endFrame()
    #expect(buffer.count > 200)
    #expect(buffer.contains(root) == true)
    var list = DrawList()
    buffer.paint(root, into: &list, in: viewport)
    #expect(list.commands.count == 600)
  }

  @Test func stackRetainsSeparatePlacementsForDifferentProposals() {
    var buffer = LayoutBuffer()
    let context = LayoutContext()
    var ignored = context
    ignored.navigationIgnored = true
    let first = buffer.color(.white, context: ignored.childScope(0))
    let second = buffer.color(.black, context: ignored.childScope(1))
    let root = buffer.stack([first, second], axis: .horizontal, spacing: 10, context: ignored)
    _ = buffer.sizeThatFits(root, Size(width: 110, height: 20))
    _ = buffer.sizeThatFits(root, Size(width: 210, height: 20))
    for width: Float in [110, 210, 110] {
      let rect = Rect(x: 0, y: 0, width: width, height: 20)
      beginTestFrame(context.interaction, input: InputState())
      buffer.register(root, in: rect)
      context.interaction.endFrame()
      var list = DrawList()
      buffer.paint(root, into: &list, in: rect)
      let quads = list.commands.compactMap { if case .quad(let q) = $0 { q.rect } else { nil } }
      #expect(quads.map(\.size.width) == [(width - 10) / 2, (width - 10) / 2])
      #expect(quads.last?.minX == (width + 10) / 2)
    }
  }

}
