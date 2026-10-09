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

  private func preparedLeaf(_ counts: Counts, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    counts.builds += 1
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

  private func wrappedLeaf(_ counts: Counts, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    counts.builds += 1
    return preparedLeaf(counts, into: &buffer, context: context.childScope(0))
  }

  private func ordinaryLeaf(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    buffer.customLeaf(
      context: context, measure: { $0 }, register: { _ in },
      paint: { $0.fillRect($1, color: .white) })
  }

  private func twoControls(_ counts: Counts, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let secondContext = context.childScope(1)
    let second = buffer.button(Button("second") { counts.actions.append(1) }, context: secondContext)
    let secondSized = buffer.sizing(second, x: .grow, y: .grow, context: secondContext)
    let firstContext = context.childScope(0)
    let first = buffer.button(Button("first") { counts.actions.append(0) }, context: firstContext)
    let firstSized = buffer.sizing(first, x: .grow, y: .grow, context: firstContext)
    return buffer.stack([firstSized, secondSized], axis: .horizontal, context: context)
  }

  @Test func publicPreparationRegistersAndPaintsOneChildWithoutReplayingEffects() {
    let counts = Counts()
    let context = LayoutContext()
    let rect = Rect(x: 0, y: 0, width: 20, height: 20)
    var preparedBuffer = LayoutBuffer()
    let prepared = wrappedLeaf(counts, into: &preparedBuffer, context: context)
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
    let context = LayoutContext()
    var preparedBuffer = LayoutBuffer()
    let prepared = preparedLeaf(counts, into: &preparedBuffer, context: context)
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
    host.build = { buffer, context in twoControls(counts, into: &buffer, context: context) }
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
    host.build = { buffer, context in
      buffer.focus(target, context: context) { buffer, context in
        ordinaryLeaf(into: &buffer, context: context)
      }
    }
    target.focus()
    host.render()
    #expect(target.isFocused)
  }

  @Test func preparedLeafOwnsExplicitFocusRegistration() {
    let counts = Counts()
    let target = FocusTarget()
    let host = HeadlessHost(size: Size(width: 20, height: 20))
    defer { host.close() }
    host.build = { buffer, context in
      buffer.focus(target, context: context) { buffer, context in
        preparedLeaf(counts, into: &buffer, context: context)
      }
    }
    target.focus()
    host.render()
    #expect(target.isFocused)
  }
}
