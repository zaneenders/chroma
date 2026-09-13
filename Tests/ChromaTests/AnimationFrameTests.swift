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
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }
    func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
      samples.timestamps.append(context.animationFrame(active: active).timestamp)
    }
  }

  @Test func sharedTimestampAndDemandFollowProducedFrames() {
    let clock = Samples()
    let producer = FrameProducer(clock: {
      clock.clockReads += 1
      return clock.now
    })
    let context = RenderContext()
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
    clock.now = 102.5  // A dropped/delayed frame uses actual time, not a fixed tick.
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
}
