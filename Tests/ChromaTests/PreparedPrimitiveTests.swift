import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct PreparedPrimitiveTests {
  final class Counts {
    var built = 0
    var registered = 0
    var painted: [String] = []
  }

  private func pair(_ counts: Counts, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    counts.built += 1
    let first = buffer.customLeaf(
      context: context.childScope(0), focusRule: .decorative, measure: { $0 },
      register: { _ in counts.registered += 1 }, paint: { _, _ in counts.painted.append("first") })
    let last = buffer.customLeaf(
      context: context.childScope(1), focusRule: .decorative, measure: { $0 },
      register: { _ in counts.registered += 1 }, paint: { _, _ in counts.painted.append("last") })
    return buffer.overlay([last, first], group: false, context: context)
  }

  @Test func emittedChildrenKeepExplicitOrderWithoutSecondConstruction() {
    let counts = Counts()
    let host = HeadlessHost()
    defer { host.close() }
    host.build = { buffer, context in pair(counts, into: &buffer, context: context) }
    host.render()
    #expect(counts.built == 2)  // Initial registration, then presentation.
    #expect(counts.registered == 4)
    #expect(counts.painted == ["last", "first"])
    host.sendInput(InputState(pointerPosition: Point(x: 1, y: 1), pointerPressed: true))
    #expect(counts.built == 3)
    #expect(counts.registered == 6)
    #expect(counts.painted == ["last", "first"])
  }

  @Test func defaultCombinedDrawingUsesTheSameLocalChildren() {
    let counts = Counts()
    let context = LayoutContext()
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = pair(counts, into: &resolvedBuffer, context: context)
      resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 20, height: 20))
      resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 20, height: 20))
    }
    context.interaction.endFrame()
    #expect(counts.built == 1)
    #expect(counts.registered == 2)
    #expect(counts.painted == ["last", "first"])
  }
}
