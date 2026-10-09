import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct LayoutBufferTests {
  private let viewport = Rect(x: 0, y: 0, width: 120, height: 80)

  @Test func commonRecordsDoNotInlineRareControlPayloads() {
    #expect(MemoryLayout<LayoutBuffer.Record>.stride <= 128)
    #expect(MemoryLayout<BlockContext>.stride <= 96)
  }

  @Test func resetAndDifferentOwnersRejectRecycledHandles() {
    var first = LayoutBuffer()
    var second = LayoutBuffer()
    let context = BlockContext()
    let old = first.emit(Color.white, context: context)
    #expect(first.contains(old) == true)
    #expect(second.contains(old) == false)
    let capacity = first.capacity
    first.reset()
    let replacement = first.emit(Color.black, context: context)
    #expect(first.capacity == capacity)
    #expect(first.contains(old) == false)
    #expect(first.contains(replacement) == true)
    #expect(old != replacement)
    second.reset()
    #expect(second.contains(replacement) == false)
  }

  @Test func directAndBuilderStacksEmitTheSameOrderedCommands() {
    let builder = VStack(spacing: 3) {
      Text("first").id("first")
      Text("second").id("second")
    }
    let direct: LayoutBuilder = { buffer, context in
      let first = buffer.emit(Text("first"), context: context.keyed("first"))
      let second = buffer.emit(Text("second"), context: context.keyed("second"))
      return buffer.stack([first, second], axis: .vertical, spacing: 3, context: context)
    }
    let host = HeadlessHost(size: viewport.size)
    defer { host.close() }
    host.setContent(builder)
    let first = host.render()
    host.build = direct
    #expect(host.render().commands == first.commands)
  }

  @Test func warmedTypedStorageGrowsOnlyWhenWorkloadGrows() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    var buffer = LayoutBuffer()
    let context = BlockContext()
    let content = VStack {
      Text("first")
      Text("second")
      Spacer()
    }
    for iteration in 0..<20 {
      PipelineMetrics.reset()
      let root = buffer.emit(content, context: context)
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
    let context = BlockContext()
    let root = buffer.emit(
      VStack(spacing: 2) {
        Text("A")
        Text("B")
      }.navigationIgnored(), context: context)
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
      context: BlockContext(),
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
    let growing = Interactive(action: {}) { _ in
      VStack {
        ForEach(0..<200, id: \.self) { _ in Text("abc") }
      }
    }
    var buffer = LayoutBuffer()
    let context = BlockContext()
    let root = buffer.emit(growing.navigationIgnored(), context: context)
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
    let context = BlockContext()
    let root = buffer.emit(
      HStack(spacing: 10) {
        Color.white
        Color.black
      }.navigationIgnored(), context: context)
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
