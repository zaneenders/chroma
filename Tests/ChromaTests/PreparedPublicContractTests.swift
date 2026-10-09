import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct PreparedPublicContractTests {
  final class Counts {
    var builds = 0
    var measurements = 0
    var registrations = 0
    var paints = 0
    var actions: [Int] = []
  }

  struct Wrapper<Content: Block>: LayoutPreparingBlock {
    let content: Content
    let counts: Counts
    var focusRule: FocusRule { .container }
    func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
      counts.builds += 1
      let child = buffer.prepare(content, context: context)
      return buffer.append(
        child: child,
        register: { buffer, rect in buffer.register(child, in: rect) },
        paint: { buffer, list, rect in buffer.paint(child, into: &list, in: rect) })
    }
  }

  struct PreparedLeaf: LayoutPreparingBlock {
    let counts: Counts
    var focusRule: FocusRule { .standard }
    func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
      counts.builds += 1
      return buffer.append(
        measure: { _, proposal in
          counts.measurements += 1
          return proposal
        },
        register: { _, rect in
          counts.registrations += 1
          context.registerFocusable(in: rect)
        },
        paint: { _, list, rect in
          counts.paints += 1
          list.fillRect(rect, color: .white)
          context.paintFocusHighlight(in: rect, into: &list)
        })
    }
  }

  struct OrdinaryLeaf: PaintableBlock {
    var focusRule: FocusRule { .standard }
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func register(in rect: Rect, context: BlockContext) {}
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      list.fillRect(rect, color: .white)
    }

  }

  struct TwoControls: LayoutPreparingBlock {
    let counts: Counts
    var focusRule: FocusRule { .container }
    func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
      let first = buffer.prepare(Button("first") { counts.actions.append(0) }, context: context.childScope(0))
      let second = buffer.prepare(Button("second") { counts.actions.append(1) }, context: context.childScope(1))
      func rectangles(_ rect: Rect) -> (Rect, Rect) {
        (
          Rect(x: rect.minX, y: rect.minY, width: rect.size.width / 2, height: rect.size.height),
          Rect(x: rect.minX + rect.size.width / 2, y: rect.minY, width: rect.size.width / 2, height: rect.size.height)
        )
      }
      return buffer.append(
        measure: { _, proposal in proposal },
        register: { buffer, rect in
          let (left, right) = rectangles(rect)
          buffer.register(first, in: left)
          buffer.register(second, in: right)
        },
        paint: { buffer, list, rect in
          let (left, right) = rectangles(rect)
          buffer.paint(second, into: &list, in: right)
          buffer.paint(first, into: &list, in: left)
        })
    }
  }

  @Test func publicPreparationRegistersAndPaintsOneChildWithoutReplayingEffects() {
    let counts = Counts()
    let context = BlockContext()
    let rect = Rect(x: 0, y: 0, width: 20, height: 20)
    var prepared = BlockEngine.prepare(
      Wrapper(content: PreparedLeaf(counts: counts), counts: counts), context: context)
    context.interaction.beginFrame(input: InputState())
    prepared.register(in: rect)
    var list = DrawList()
    prepared.paint(into: &list, in: rect)
    prepared.paint(into: &list, in: rect)
    context.interaction.endFrame()
    #expect(counts.builds == 2)
    #expect(counts.registrations == 1)
    #expect(counts.paints == 2)
    #expect(list.paintSnapshot.filter { if case .fillRect = $0 { true } else { false } }.count == 2)
  }

  @Test func measurementDoesNotRunRegistrationOrPainting() {
    let counts = Counts()
    let context = BlockContext()
    var prepared = BlockEngine.prepare(PreparedLeaf(counts: counts), context: context)
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
