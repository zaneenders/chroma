import Chroma
import ChromaTesting
import Testing

@MainActor
struct PreparedPublicContractTests {
  final class Counts {
    var builds = 0
    var measurements = 0
    var registrations = 0
    var paints = 0
    var actions: [Int] = []
  }

  struct LegacyLeaf: PrimitiveBlock {
    let counts: Counts
    var focusRule: FocusRule { .decorative }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      counts.measurements += 1
      return proposal
    }
    func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      counts.paints += 1
      list.fillRect(rect, color: .white)
    }
  }

  struct Wrapper<Content: Block>: LayoutPreparingBlock {
    let content: Content
    let counts: Counts
    var focusRule: FocusRule { .container }
    func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
      counts.builds += 1
      let child = BlockEngine.prepare(content, context: context)
      return BlockEngine.Resolved(child: child, register: child.register, paint: child.paint)
    }
  }

  struct DirectContainer: PrimitiveBlock {
    let content: any PrimitiveBlock
    var focusRule: FocusRule { .container }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      content.sizeThatFits(proposal, context: context)
    }
    func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      // Legacy wrappers can call concrete container draw entry points during input refresh.
      content.draw(into: &list, in: rect, context: context)
    }
  }

  struct PreparedLeaf: LayoutPreparingBlock {
    let counts: Counts
    var focusRule: FocusRule { .standard }
    func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
      counts.builds += 1
      return BlockEngine.Resolved(
        measure: { proposal in
          counts.measurements += 1
          return proposal
        },
        register: { rect in
          counts.registrations += 1
          context.registerFocusable(in: rect)
        },
        paint: { list, rect in
          counts.paints += 1
          list.fillRect(rect, color: .white)
          context.paintFocusHighlight(in: rect, into: &list)
        })
    }
  }

  struct OrdinaryLeaf: PaintableBlock {
    var focusRule: FocusRule { .standard }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func register(in rect: Rect, context: BlockContext) {}
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      list.fillRect(rect, color: .white)
    }
    func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      paint(into: &list, in: rect, context: context)
    }
  }

  struct TwoControls: LayoutPreparingBlock {
    let counts: Counts
    var focusRule: FocusRule { .container }
    func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
      let first = BlockEngine.prepare(Button("first") { counts.actions.append(0) }, context: context.childScope(0))
      let second = BlockEngine.prepare(Button("second") { counts.actions.append(1) }, context: context.childScope(1))
      func rectangles(_ rect: Rect) -> (Rect, Rect) {
        (
          Rect(x: rect.minX, y: rect.minY, width: rect.size.width / 2, height: rect.size.height),
          Rect(x: rect.minX + rect.size.width / 2, y: rect.minY, width: rect.size.width / 2, height: rect.size.height)
        )
      }
      return BlockEngine.Resolved(
        measure: { $0 },
        register: { rect in
          let (left, right) = rectangles(rect)
          first.register(in: left)
          second.register(in: right)
        },
        paint: { list, rect in
          let (left, right) = rectangles(rect)
          second.paint(into: &list, in: right)
          first.paint(into: &list, in: left)
        })
    }
  }

  @Test func defaultCombinedDrawingAdaptsLegacyChildrenExactlyOnce() {
    let counts = Counts()
    var list = DrawList()
    BlockEngine.draw(
      Wrapper(content: LegacyLeaf(counts: counts), counts: counts), into: &list,
      in: Rect(x: 0, y: 0, width: 20, height: 20), context: BlockContext())
    #expect(counts.builds == 1)
    #expect(counts.paints == 1)
    #expect(list.commands.count == 1)
  }

  @Test func directPrimitiveDrawingAdaptsLegacyChildrenExactlyOnce() {
    let counts = Counts()
    var list = DrawList()
    Wrapper(content: LegacyLeaf(counts: counts), counts: counts).draw(
      into: &list, in: Rect(x: 0, y: 0, width: 20, height: 20), context: BlockContext())
    #expect(counts.builds == 1)
    #expect(counts.paints == 1)
    #expect(list.commands.count == 1)
  }

  @Test func measurementDoesNotRunRegistrationOrPainting() {
    let counts = Counts()
    let context = BlockContext()
    let prepared = BlockEngine.prepare(PreparedLeaf(counts: counts), context: context)
    let proposal = Size(width: 20, height: 20)
    #expect(prepared.sizeThatFits(proposal) == proposal)
    #expect(prepared.sizeThatFits(proposal) == proposal)
    #expect(counts.builds == 1)
    #expect(counts.measurements == 1)
    #expect(counts.registrations == 0)
    #expect(counts.paints == 0)
  }

  @Test func reorderedPaintPreservesIndependentChildActions() {
    let counts = Counts()
    let host = HeadlessHost(size: Size(width: 100, height: 30))
    defer { host.close() }
    host.content = TwoControls(counts: counts)
    host.render()
    for x: Float in [10, 70, 10] {
      let point = Point(x: x, y: 10)
      host.sendInput(
        InputState(pointerPosition: point, pointerPressPosition: point, pointerDown: true, pointerPressed: true))
      host.sendInput(InputState(pointerPosition: point, pointerReleased: true))
    }
    #expect(counts.actions == [0, 1, 0])
  }

  @Test func ordinaryLeafKeepsAutomaticPrimitiveFocusRegistration() {
    let target = FocusTarget()
    let host = HeadlessHost(size: Size(width: 20, height: 20))
    defer { host.close() }
    host.content = OrdinaryLeaf().focusTarget(target)
    target.focus()
    host.render()
    #expect(target.isFocused)
  }

  @Test(arguments: 0..<5)
  func directContainersAdaptNestedLegacyChildrenExactlyOnce(kind: Int) {
    let counts = Counts()
    let wrapper = Wrapper(content: LegacyLeaf(counts: counts), counts: counts)
    let container: any PrimitiveBlock
    switch kind {
    case 0: container = VStack { wrapper }
    case 1: container = HStack { wrapper }
    case 2: container = TupleBlock(children: [wrapper])
    case 3: container = ZStack { wrapper }
    default: container = ScrollView(showsIndicator: false) { wrapper }
    }
    let host = HeadlessHost(size: Size(width: 20, height: 20))
    defer { host.close() }
    host.content = DirectContainer(content: container)
    let frame = host.render()
    // Initial input registration and presentation each adapt the child exactly once.
    #expect(counts.paints == 2)
    #expect(frame.commands.filter { if case .fillRect = $0 { true } else { false } }.count == 1)
  }

  @Test func preparedLeafOwnsExplicitFocusRegistration() {
    let counts = Counts()
    let target = FocusTarget()
    let host = HeadlessHost(size: Size(width: 20, height: 20))
    defer { host.close() }
    host.content = PreparedLeaf(counts: counts).focusTarget(target)
    target.focus()
    host.render()
    #expect(target.isFocused)
  }
}
