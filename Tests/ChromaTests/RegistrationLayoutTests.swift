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

  struct Leaf: PaintableBlock {
    let state: State
    var focusRule: FocusRule { .standard }
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      state.measures += 1
      return Size(width: 30, height: state.height)
    }
    func register(in rect: Rect, context: BlockContext) { state.rects.append(rect) }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      state.paints += 1
      list.fillRect(rect, color: .white)
    }
  }

  @Test func registrationSharesProposalMeasurementsOnlyWithinItsOperation() {
    let state = State()
    let block = VStack { VStack { Leaf(state: state) }.padding(3) }
    let context = BlockContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 60)
    let resolved = BlockEngine.resolve(block, context: context)
    #expect(resolved.sizeThatFits(rect.size).height == 18)
    let before = state.measures
    _ = resolved.sizeThatFits(rect.size)
    #expect(state.measures == before)
    context.interaction.beginFrame(input: InputState())
    resolved.register(in: rect)
    context.interaction.endFrame()
    #expect(state.paints == 0)
    #expect(state.rects.last?.size.height == 12)

    state.height = 28
    FrameProducer().refreshRegistrations(block, viewport: rect.size, context: context)
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
    producer.refreshRegistrations(block, viewport: viewport, context: context)
    #expect(second.rects.last?.minY == 23)
    first.height = 32  // Intentionally not observed: event reconciliation must remain conservative.
    producer.refreshRegistrations(block, viewport: viewport, context: context)
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
    FrameProducer().refreshRegistrations(block, viewport: Size(width: 300, height: 200), context: BlockContext())
    let counts = PipelineMetrics.snapshot
    #expect(counts.registrations > 0)
    #expect(counts.paints == 0)
    #expect(counts.drawingCommands == 0)
    #expect(counts.liveResolvedNodes == 0)
  }

}
