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

    let state: State
    var focusRule: FocusRule { .standard }
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      state.measures += 1
      return Size(width: 30, height: state.height)
    }
    @MainActor func register(in rect: Rect, context: BlockContext) { state.rects.append(rect) }
    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      state.paints += 1
      list.fillRect(rect, color: .white)
    }
  }

  @Test func registrationSharesProposalMeasurementsOnlyWithinItsOperation() {
    let state = State()
    let block = VStack { VStack { Leaf(state: state) }.padding(3) }
    let context = BlockContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 60)
    var resolvedBuffer = LayoutBuffer()
    let resolved = resolvedBuffer.emit(block, context: context)
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
      { buffer, context in buffer.emit(block, context: context) }, viewport: rect.size, context: context)
    #expect(state.rects.last?.size.height == 28)
  }

  @Test func changedIntrinsicSizeRepositionsParentAndFollowingSiblingBeforeInput() {
    let first = State()
    let second = State()
    let block = VStack(spacing: 5) {
      VStack { Leaf(state: first) }.padding(3)
      Leaf(state: second)
    }
    let context = BlockContext()
    let producer = FrameProducer()
    let viewport = Size(width: 100, height: 100)
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(block, context: context) }, viewport: viewport, context: context)
    #expect(second.rects.last?.minY == 23)
    first.height = 32  // Intentionally not observed: event reconciliation must remain conservative.
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(block, context: context) }, viewport: viewport, context: context)
    #expect(second.rects.last?.minY == 43)
    #expect(first.paints == 0)
    #expect(second.paints == 0)
  }

  @Test func preparedBuiltinsRegisterWithoutPainting() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let target = FocusTarget()
    let block = ThemeReader { _ in
      Group("root") {
        ZStack {
          HStack {
            VStack {
              Text("label").selectable().wrapping()
              MarqueeText("marquee")
              ProgressIndicator()
              Spacer()
              EmptyBlock()
            }
            TrailingControlsRow(spacing: 4) {
              TextEditor(text: { "abc" }, onChange: { _ in })
            } controls: {
              Button("Save") {}.focusTarget(target)
            }
          }.padding(3).border(.white).clipped().background(Color.black)
        }
      }
    }.chromaTheme(.dark)
    FrameProducer().refreshRegistrations(
      { buffer, context in buffer.emit(block, context: context) }, viewport: Size(width: 300, height: 200),
      context: BlockContext())
    let counts = PipelineMetrics.snapshot
    #expect(counts.registrations > 0)
    #expect(counts.paints == 0)
    #expect(counts.drawingCommands == 0)
  }

}
