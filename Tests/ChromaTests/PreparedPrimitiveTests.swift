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

  struct Leaf: PaintableBlock {
    let name: String
    let counts: Counts
    var focusRule: FocusRule { .decorative }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func register(in rect: Rect, context: BlockContext) { counts.registered += 1 }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) { counts.painted.append(name) }

  }

  struct Pair: LayoutPreparingBlock {
    let counts: Counts
    var focusRule: FocusRule { .container }
    func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
      counts.built += 1
      let first = buffer.prepare(Leaf(name: "first", counts: counts), context: context)
      let last = buffer.prepare(Leaf(name: "last", counts: counts), context: context)
      return buffer.append(
        measure: { buffer, proposal in buffer.sizeThatFits(first, proposal) },
        register: { buffer, rect in
          buffer.register(first, in: rect)
          buffer.register(last, in: rect)
        },
        paint: { buffer, list, rect in
          // Local child ownership permits compositing order independent of visitation order.
          buffer.paint(last, into: &list, in: rect)
          buffer.paint(first, into: &list, in: rect)
        })
    }
  }

  @Test func localChildrenNeedNoMatchingTraversalOrSecondConstruction() {
    let counts = Counts()
    let host = HeadlessHost()
    defer { host.close() }
    host.content = Pair(counts: counts)
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
      var resolved = BlockEngine.prepare(Pair(counts: counts), context: BlockContext())
      resolved.register(in: Rect(x: 0, y: 0, width: 20, height: 20))
      resolved.paint(into: &list, in: Rect(x: 0, y: 0, width: 20, height: 20))
    }
    #expect(counts.built == 1)
    #expect(counts.registered == 2)
    #expect(counts.painted == ["last", "first"])
  }
}
