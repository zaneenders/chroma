import Testing

@testable import Chroma

@MainActor
struct AnimatedValueTests {
  final class Model {
    var now = 0.0
    var target: Float = 10
    var reversed = false
    var visible = true
  }

  private func render(_ runtime: WindowRuntime) -> DrawList {
    runtime.scheduler.recordProducedFrame()
    runtime.scheduler.consumeContentRequest()
    return runtime.render(viewport: Size(width: 200, height: 100), input: InputState(), onChange: {})
  }

  @Test func sampledGeometryIsSharedAndRetargetingIsContinuous() throws {
    let model = Model()
    let runtime = WindowRuntime(clock: { model.now })
    runtime.build = { buffer, context in
      let animated = buffer.animatedValue(model.target, duration: 1, context: context.keyed("animated")) {
        buffer, context, value in
        let color = buffer.color(.white, context: context)
        return buffer.sizing(color, x: .fixed(value), y: .fixed(10), context: context)
      }
      return buffer.stack([animated], axis: .vertical, context: context)
    }
    func width(_ list: DrawList) throws -> Float {
      try #require(list.commands.compactMap { if case .quad(let q) = $0 { q.rect.size.width } else { nil } }.first)
    }
    #expect(try width(render(runtime)) == 10)
    #expect(!runtime.scheduler.animationsActive)
    model.target = 110
    #expect(try width(render(runtime)) == 10)
    #expect(runtime.scheduler.animationsActive)
    model.now = 0.5
    let half = render(runtime)
    #expect(try width(half) == 60)
    #expect(try width(render(runtime)) == 60)
    model.target = 10
    #expect(try width(render(runtime)) == 60)
    model.now = 1
    #expect(try width(render(runtime)) == 35)
    model.now = 1.5
    #expect(try width(render(runtime)) == 10)
    #expect(!runtime.scheduler.animationsActive)
    #expect(runtime.scheduler.nextFrame == nil)
    #expect(try width(half) == 60)
  }

  @Test func keyedReorderPreservesProgressAndRemovalCancelsIt() {
    let model = Model()
    let runtime = WindowRuntime(clock: { model.now })
    runtime.build = { buffer, context in
      var children: [LayoutNode] = []
      if model.visible {
        for id in model.reversed ? [2, 1] : [1, 2] {
          children.append(
            buffer.animatedValue(model.target + Float(id), duration: 1, context: context.keyed(id)) {
              buffer, context, value in
              let color = buffer.color(.white, context: context)
              return buffer.sizing(color, x: .fixed(value), y: .fixed(10), context: context)
            })
        }
      }
      return buffer.stack(children, axis: .vertical, context: context)
    }
    _ = render(runtime)
    model.target = 110
    _ = render(runtime)
    let keys = Set(runtime.interaction.animations.keys)
    model.now = 0.5
    model.reversed = true
    _ = render(runtime)
    #expect(Set(runtime.interaction.animations.keys) == keys)
    #expect(runtime.interaction.animations.values.allSatisfy { $0.start == 0 })
    model.visible = false
    _ = render(runtime)
    #expect(runtime.interaction.animations.isEmpty)
    #expect(!runtime.scheduler.animationsActive)
    #expect(runtime.scheduler.nextFrame == nil)
    model.visible = true
    _ = render(runtime)
    #expect(runtime.interaction.animations.values.allSatisfy { $0.from == $0.target })
    runtime.reset()
    #expect(runtime.interaction.animations.isEmpty)
  }

  @Test func zeroDurationSnapsAndPaintDoesNotAdvanceState() {
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    context.interaction.animationTime = 1
    let root = buffer.animatedValue(20, duration: 0, context: context) { buffer, context, _ in
      buffer.color(.white, context: context)
    }
    _ = buffer.sizeThatFits(root, Size(width: 20, height: 20))
    #expect(context.interaction.animations.isEmpty)
    beginTestFrame(context.interaction, input: InputState())
    let rect = Rect(x: 0, y: 0, width: 20, height: 20)
    buffer.register(root, in: rect)
    context.interaction.endFrame()
    let state = context.interaction.animations.values.first!
    var list = DrawList()
    buffer.paint(root, into: &list, in: rect)
    context.interaction.animationTime = 2
    buffer.paint(root, into: &list, in: rect)
    #expect(context.interaction.animations.values.first!.start == state.start)
    #expect(!context.interaction.animationsActive)
  }

  @Test func idleMeasurementCannotRetargetTheRegisteredInteractivePhase() {
    let model = Model()
    let runtime = WindowRuntime(clock: { model.now })
    runtime.build = { buffer, context in
      buffer.interactive(
        action: {},
        content: { buffer, context, phase in
          buffer.animatedValue(phase == .idle ? 10 : 100, duration: 1, context: context) { buffer, context, value in
            let color = buffer.color(.white, context: context)
            return buffer.sizing(color, x: .fixed(value), y: .fixed(10), context: context)
          }
        }, context: context)
    }
    _ = render(runtime)
    runtime.handleInput(InputState(pointerPosition: Point(x: 5, y: 5)))
    _ = render(runtime)
    model.now = 0.5
    _ = render(runtime)
    model.now = 1.1
    _ = render(runtime)
    #expect(runtime.interaction.animations.values.allSatisfy { $0.target == 100 && $0.start == 0 })
    #expect(!runtime.scheduler.animationsActive)
  }

  @Test func finiteEndpointsInterpolateWithoutOverflowAndFinishExactly() {
    let state = ScalarAnimation(
      from: -Float.greatestFiniteMagnitude, target: .greatestFiniteMagnitude, start: 0, duration: 1)
    #expect(state.value(at: 0) == -Float.greatestFiniteMagnitude)
    #expect(state.value(at: 0.5) == 0)
    #expect(state.value(at: 1) == Float.greatestFiniteMagnitude)
  }

}
