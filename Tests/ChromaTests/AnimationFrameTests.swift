import Observation
import Testing

@testable import Chroma

@MainActor
struct AnimationFrameTests {
  final class Samples {
    var timestamps: [Double] = []
    var now = 100.0
    var clockReads = 0
  }

  struct Animated: PrimitiveBlock {
    let samples: Samples
    var active = true
    var focusRule: FocusRule { .standard }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
      context.animate(into: &drawList, isActive: active) { _, frame in
        samples.timestamps.append(frame.timestamp)
      }
    }
  }

  @Test func readingTimeDoesNotScheduleAnimation() {
    let context = BlockContext()
    context.interaction.animationFrame = AnimationFrame(timestamp: 100.01)
    #expect(context.animationTimestamp == 100.01)
    #expect(context.interaction.animationPaints.isEmpty)
  }

  @Test func sharedTimestampAndDemandFollowProducedFrames() {
    let clock = Samples()
    let producer = FrameProducer(clock: {
      clock.clockReads += 1
      return clock.now
    })
    let context = BlockContext()
    let samples = Samples()
    func render(_ content: any Block) {
      _ = producer.render(
        content: content, viewport: Size(width: 100, height: 100),
        input: InputState(), context: context, onChange: {})
    }
    render(
      HStack {
        Animated(samples: samples)
        Animated(samples: samples)
      })
    #expect(clock.clockReads == 1)
    #expect(samples.timestamps.allSatisfy { $0 == 100 })
    #expect(producer.needsAnimationFrame)

    samples.timestamps = []
    clock.now = 102.5
    render(
      HStack {
        Animated(samples: samples)
        Animated(samples: samples)
      })
    #expect(samples.timestamps == [102.5, 102.5])
    #expect(clock.clockReads == 2)

    render(Animated(samples: samples, active: false))
    #expect(!producer.needsAnimationFrame)
    render(Animated(samples: samples))
    #expect(producer.needsAnimationFrame)
    render(EmptyBlock())
    #expect(!producer.needsAnimationFrame)
    render(Animated(samples: samples))
    producer.reset()
    #expect(!producer.needsAnimationFrame)
  }
  @Observable final class PaintModel {
    var color = Color.white
  }

  @Test(ControlledObservationDelivery())
  func animationPaintReusesStaticCommandsAndPreservesObservation() async {
    let clock = Samples()
    let producer = FrameProducer(clock: { clock.now })
    let context = BlockContext()
    let model = PaintModel()
    var builds = 0
    var changes = 0
    let content = DeferredBlock {
      builds += 1
      return Painted(model: model)
    }
    let first = producer.render(
      content: content, viewport: Size(width: 100, height: 100), input: InputState(),
      context: context, onChange: { changes += 1 })
    let initialBuilds = builds
    clock.now += 0.1
    let second = producer.renderAnimations()
    #expect(builds == initialBuilds)
    #expect(second.commands.first == first.commands.first)
    #expect(second.commands.last == first.commands.last)
    #expect(second.commands != first.commands)
    // Paint output may change length; ranges always refer to the cached content frame.
    clock.now += 1
    #expect(producer.renderAnimations().commands.count == first.commands.count + 1)
    #expect(builds == initialBuilds)
    model.color = .yellow
    await drainObservationChanges()
    #expect(changes == 1)
    producer.reset()
    #expect(producer.renderAnimations().commands.isEmpty)
    #expect(!producer.needsAnimationFrame)
  }

  @Test func caretAnimationDoesNotRebuildEditorAndStopsWithSelection() throws {
    let samples = Samples()
    let producer = FrameProducer(clock: { samples.now })
    let context = BlockContext()
    var builds = 0
    let editor = DeferredBlock {
      builds += 1
      return TextEditor(singleLine: true, text: { "abc" }, onChange: { _ in })
    }
    func render() -> DrawList {
      producer.render(
        content: editor, viewport: Size(width: 200, height: 40), input: InputState(),
        context: context, onChange: {})
    }
    _ = render()
    let tree = try #require(context.interaction.tree)
    let path = try #require(tree.firstLeafPath())
    context.focus(try #require(tree.node(at: path)?.leafID), editing: true)
    _ = render()
    #expect(producer.needsAnimationFrame)
    let initialBuilds = builds
    samples.now = 100.8
    let hidden = producer.renderAnimations()
    #expect(builds == initialBuilds)
    #expect(
      !hidden.commands.contains {
        if case .fillRect(_, let color) = $0 {
          return color == context.theme.textEditor.caret
        }
        return false
      })
    samples.now = 101.3
    #expect(
      producer.renderAnimations().commands.contains {
        if case .fillRect(_, let color) = $0 {
          return color == context.theme.textEditor.caret
        }
        return false
      })
    #expect(builds == initialBuilds)
    context.interaction.textSelectionRange = 0..<2
    _ = render()
    #expect(!producer.needsAnimationFrame)
    producer.reset()
  }

  @Test func multipleAnimationRangesShareTimeAndDoNotAccumulateCommands() {
    let clock = Samples()
    let samples = Samples()
    let producer = FrameProducer(clock: { clock.now })
    let context = BlockContext()
    let content = HStack {
      Text("static")
      Animated(samples: samples)
      ProgressIndicator()
      Animated(samples: samples)
    }
    let first = producer.render(
      content: content, viewport: Size(width: 200, height: 50),
      input: InputState(), context: context, onChange: {})
    samples.timestamps = []
    clock.now += 1
    let second = producer.renderAnimations()
    #expect(samples.timestamps == [101, 101])
    #expect(second.commands.count == first.commands.count)
    #expect(
      second.commands.contains {
        if case .text(_, "static", _, _) = $0 { return true }
        return false
      })
    for _ in 0..<5 { #expect(producer.renderAnimations().commands.count == first.commands.count) }
    producer.reset()
  }

  @Test func contentReplacementReplacesCommandsAndAnimationRangesTogether() {
    let clock = Samples()
    let producer = FrameProducer(clock: { clock.now })
    let context = BlockContext()
    func render(_ content: any Block) -> DrawList {
      producer.render(
        content: content, viewport: Size(width: 200, height: 50),
        input: InputState(), context: context, onChange: {})
    }
    _ = render(HStack { Text("Old prefix"); Painted(model: PaintModel()); Text("Old suffix") })
    clock.now = 102
    _ = producer.renderAnimations()
    let replacement = render(ProgressIndicator())
    #expect(producer.needsAnimationFrame)
    #expect(producer.renderAnimations().commands == replacement.commands)
    clock.now += 1
    #expect(producer.renderAnimations().commands.count == replacement.commands.count)
    let staticFrame = render(Text("Replacement"))
    #expect(!producer.needsAnimationFrame)
    #expect(producer.renderAnimations().commands == staticFrame.commands)
    _ = render(Painted(model: PaintModel()))
    let emptyFrame = render(EmptyBlock())
    #expect(!producer.needsAnimationFrame)
    #expect(producer.renderAnimations().commands == emptyFrame.commands)
    producer.reset()
    #expect(producer.renderAnimations().commands.isEmpty)
  }

  @Test func contentReplacementReleasesPreviousAnimationCaptures() {
    let producer = FrameProducer()
    let context = BlockContext()
    weak var released: PaintModel?
    do {
      let model = PaintModel()
      released = model
      _ = producer.render(
        content: RetainedPaint(model: model), viewport: Size(width: 100, height: 100),
        input: InputState(), context: context, onChange: {})
    }
    #expect(released != nil)
    let replacement = producer.render(
      content: Text("Static"), viewport: Size(width: 100, height: 100),
      input: InputState(), context: context, onChange: {})
    #expect(released == nil)
    #expect(!producer.needsAnimationFrame)
    #expect(producer.renderAnimations().commands == replacement.commands)
    producer.reset()
  }

  @Test func resetReleasesCachedAnimationCaptures() {
    let producer = FrameProducer()
    weak var released: PaintModel?
    do {
      let model = PaintModel()
      released = model
      _ = producer.render(
        content: RetainedPaint(model: model), viewport: Size(width: 100, height: 100),
        input: InputState(), context: BlockContext(), onChange: {})
    }
    #expect(released != nil)
    producer.reset()
    #expect(released == nil)
  }

  struct RetainedPaint: PrimitiveBlock {
    let model: PaintModel
    var focusRule: FocusRule { .decorative }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
      context.animate(into: &drawList) { list, _ in list.fillRect(rect, color: model.color) }
    }
  }

  struct Painted: PrimitiveBlock {
    let model: PaintModel
    var focusRule: FocusRule { .decorative }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
      drawList.pushClip(rect)
      let color = model.color
      context.animate(into: &drawList) { list, frame in
        list.text(String(frame.timestamp), at: .zero, color: color)
        if frame.timestamp > 101 { list.fillRect(rect, color: color) }
      }
      drawList.popClip()
    }
  }

}
