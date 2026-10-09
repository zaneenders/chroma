import Chroma
import ChromaTesting
import Testing

@MainActor
struct PreparedPrimitiveTests {
  final class Counts {
    var built = 0
    var registered = 0
    var painted: [String] = []
  }

  struct Leaf: Block {

    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        expandsHorizontally: false, expandsVertically: false,
        measure: { sizeThatFits($0, context: context) },
        register: { register(in: $0, context: context) },
        paint: { paint(into: &$0, in: $1, context: context) })
    }

    let name: String
    let counts: Counts
    var focusRule: FocusRule { .decorative }
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    @MainActor func register(in rect: Rect, context: BlockContext) { counts.registered += 1 }
    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) { counts.painted.append(name) }

  }

  struct Pair: Block {
    let counts: Counts
    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      counts.built += 1
      let context = context.component(Self.self)
      let first = buffer.emit(Leaf(name: "first", counts: counts), context: context.childScope(0))
      let last = buffer.emit(Leaf(name: "last", counts: counts), context: context.childScope(1))
      return buffer.overlay([last, first], group: false, context: context)
    }
  }

  @Test func emittedChildrenKeepExplicitOrderWithoutSecondConstruction() {
    let counts = Counts()
    let host = HeadlessHost()
    defer { host.close() }
    host.setContent(Pair(counts: counts))
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
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(Pair(counts: counts), context: BlockContext())
      resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 20, height: 20))
      resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 20, height: 20))
    }
    #expect(counts.built == 1)
    #expect(counts.registered == 2)
    #expect(counts.painted == ["last", "first"])
  }
}
