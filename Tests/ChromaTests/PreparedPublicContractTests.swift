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

  struct Wrapper<Content: Block>: Block {
    let content: Content
    let counts: Counts
    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      counts.builds += 1
      return buffer.emit(content, context: context.component(Self.self))
    }
  }

  struct PreparedLeaf: Block {
    let counts: Counts
    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      counts.builds += 1
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: .container,
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

  struct OrdinaryLeaf: Block {

    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        expandsHorizontally: false, expandsVertically: false,
        measure: { sizeThatFits($0, context: context) },
        register: { register(in: $0, context: context) },
        paint: { paint(into: &$0, in: $1, context: context) })
    }

    var focusRule: FocusRule { .standard }
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    @MainActor func register(in rect: Rect, context: BlockContext) {}
    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      list.fillRect(rect, color: .white)
    }

  }

  struct TwoControls: Block {
    let counts: Counts
    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      let second = buffer.emit(
        Button("second") { counts.actions.append(1) }.sizing(x: .grow, y: .grow),
        context: context.childScope(1))
      let first = buffer.emit(
        Button("first") { counts.actions.append(0) }.sizing(x: .grow, y: .grow),
        context: context.childScope(0))
      return buffer.stack([first, second], axis: .horizontal, context: context)
    }
  }

  @Test func publicPreparationRegistersAndPaintsOneChildWithoutReplayingEffects() {
    let counts = Counts()
    let context = BlockContext()
    let rect = Rect(x: 0, y: 0, width: 20, height: 20)
    var preparedBuffer = LayoutBuffer()
    let prepared = preparedBuffer.emit(
      Wrapper(content: PreparedLeaf(counts: counts), counts: counts), context: context)
    beginTestFrame(context.interaction, input: InputState())
    preparedBuffer.register(prepared, in: rect)
    var list = DrawList()
    preparedBuffer.paint(prepared, into: &list, in: rect)
    preparedBuffer.paint(prepared, into: &list, in: rect)
    context.interaction.endFrame()
    #expect(counts.builds == 2)
    #expect(counts.registrations == 1)
    #expect(counts.paints == 2)
    #expect(list.paintSnapshot.filter { if case .fillRect = $0 { true } else { false } }.count == 2)
  }

  @Test func measurementDoesNotRunRegistrationOrPainting() {
    let counts = Counts()
    let context = BlockContext()
    var preparedBuffer = LayoutBuffer()
    let prepared = preparedBuffer.emit(PreparedLeaf(counts: counts), context: context)
    let proposal = Size(width: 20, height: 20)
    #expect(preparedBuffer.sizeThatFits(prepared, proposal) == proposal)
    #expect(preparedBuffer.sizeThatFits(prepared, proposal) == proposal)
    #expect(counts.builds == 1)
    #expect(counts.measurements == 1)
    #expect(counts.registrations == 0)
    #expect(counts.paints == 0)
  }

  @Test func reorderedEmissionPreservesIndependentChildActions() {
    let counts = Counts()
    let host = HeadlessHost(size: Size(width: 100, height: 30))
    defer { host.close() }
    host.setContent(TwoControls(counts: counts))
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
    host.setContent(OrdinaryLeaf().focusTarget(target))
    target.focus()
    host.render()
    #expect(target.isFocused)
  }

  @Test func preparedLeafOwnsExplicitFocusRegistration() {
    let counts = Counts()
    let target = FocusTarget()
    let host = HeadlessHost(size: Size(width: 20, height: 20))
    defer { host.close() }
    host.setContent(PreparedLeaf(counts: counts).focusTarget(target))
    target.focus()
    host.render()
    #expect(target.isFocused)
  }
}
