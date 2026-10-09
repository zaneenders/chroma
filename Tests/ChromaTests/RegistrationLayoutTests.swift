import Testing

@testable import Chroma

@MainActor
struct RegistrationLayoutTests {
  final class State {
    var height: Float = 12
    var measures = 0
    var rects: [Rect] = []
    var paints = 0
  }

  private func leaf(_ state: State, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    buffer.customLeaf(
      context: context,
      measure: { _ in
        state.measures += 1
        return Size(width: 30, height: state.height)
      },
      register: { state.rects.append($0) },
      paint: { list, rect in
        state.paints += 1
        list.fillRect(rect, color: .white)
      })
  }

  @Test func registrationSharesProposalMeasurementsOnlyWithinItsOperation() {
    let state = State()
    let build: LayoutBuilder = { buffer, context in
      let leaf = leaf(state, into: &buffer, context: context.childScope(0).childScope(0))
      let inner = buffer.stack([leaf], axis: .vertical, context: context.childScope(0))
      let padded = buffer.padding(inner, 3, context: context.childScope(0))
      return buffer.stack([padded], axis: .vertical, context: context)
    }
    let context = LayoutContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 60)
    var resolvedBuffer = LayoutBuffer()
    let resolved = build(&resolvedBuffer, context)
    #expect(resolvedBuffer.sizeThatFits(resolved, rect.size).height == 18)
    let before = state.measures
    _ = resolvedBuffer.sizeThatFits(resolved, rect.size)
    #expect(state.measures == before)
    beginTestFrame(context.interaction, input: InputState())
    resolvedBuffer.register(resolved, in: rect)
    context.interaction.endFrame()
    #expect(state.paints == 0)
    #expect(state.rects.last?.size.height == 12)

    state.height = 28
    FrameProducer().refreshRegistrations(
      build, viewport: rect.size, context: context)
    #expect(state.rects.last?.size.height == 28)
  }

  @Test func changedIntrinsicSizeRepositionsParentAndFollowingSiblingBeforeInput() {
    let first = State()
    let second = State()
    let build: LayoutBuilder = { buffer, context in
      let firstLeaf = leaf(first, into: &buffer, context: context.childScope(0).childScope(0))
      let inner = buffer.stack([firstLeaf], axis: .vertical, context: context.childScope(0))
      let padded = buffer.padding(inner, 3, context: context.childScope(0))
      let secondLeaf = leaf(second, into: &buffer, context: context.childScope(1))
      return buffer.stack([padded, secondLeaf], axis: .vertical, spacing: 5, context: context)
    }
    let context = LayoutContext()
    let producer = FrameProducer()
    let viewport = Size(width: 100, height: 100)
    producer.refreshRegistrations(
      build, viewport: viewport, context: context)
    #expect(second.rects.last?.minY == 23)
    first.height = 32  // Intentionally not observed: event reconciliation must remain conservative.
    producer.refreshRegistrations(
      build, viewport: viewport, context: context)
    #expect(second.rects.last?.minY == 43)
    #expect(first.paints == 0)
    #expect(second.paints == 0)
  }

  @Test func preparedBuiltinsRegisterWithoutPainting() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let target = FocusTarget()
    let build: LayoutBuilder = { buffer, context in
      buffer.group("root", context: context.withTheme(.dark)) { buffer, context in
        buffer.background(
          context: context,
          content: { buffer, context in
            let leftContext = context.childScope(0)
            let text = buffer.text(Text("label").selectable().wrapping(), context: leftContext.childScope(0))
            let marquee = buffer.marqueeText(MarqueeText("marquee"), context: leftContext.childScope(1))
            let progress = buffer.progressIndicator(ProgressIndicator(), context: leftContext.childScope(2))
            let spacer = buffer.spacer(context: leftContext.childScope(3))
            let empty = buffer.empty(context: leftContext.childScope(4))
            let left = buffer.stack([text, marquee, progress, spacer, empty], axis: .vertical, context: leftContext)
            let right = buffer.trailingControls(
              spacing: 4, context: context.childScope(1),
              input: { $0.textEditor(TextEditor(text: { "abc" }, onChange: { _ in }), context: $1) },
              controls: { buffer, context in
                buffer.focus(target, context: context) { $0.button(Button("Save") {}, context: $1) }
              })
            let row = buffer.stack([left, right], axis: .horizontal, context: context)
            let padded = buffer.padding(row, 3, context: context)
            let border = buffer.border(padded, color: .white, context: context)
            let clipped = buffer.clip(border, context: context)
            return buffer.overlay([clipped], context: context)
          }, background: { $0.color(.black, context: $1) })
      }
    }
    FrameProducer().refreshRegistrations(
      build, viewport: Size(width: 300, height: 200),
      context: LayoutContext())
    let counts = PipelineMetrics.snapshot
    #expect(counts.registrations > 0)
    #expect(counts.paints == 0)
    #expect(counts.drawingCommands == 0)
  }

}
