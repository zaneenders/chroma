import Foundation
import Testing

@testable import Chroma

@MainActor
struct NodePaintPrimitiveTests {
  private final class Clock { var now = 1.0 }

  private let viewport = Size(width: 80, height: 30)

  @Test func paintMatchesLegacyWithoutChangingRegistrations() throws {
    let resource = try ImageResource(id: ImageID("pixel"), width: 1, height: 1, rgba8: Data([255, 0, 0, 255]))
    let primitives: [any Block] = [
      Image(resource, scaling: .cover, alignment: .bottomTrailing),
      ProgressIndicator(diameter: 18),
      MarqueeText("A long scrolling label"),
    ]
    for primitive in primitives {
      let context = BlockContext()
      context.interaction.animationFrame = AnimationFrame(timestamp: 1.2)
      let scene = NodeScene()
      try scene.update(primitive, context: context)
      let rect = Rect(origin: .zero, size: viewport)
      #expect(try scene.layout(in: rect) == BlockEngine.measure(primitive, proposal: viewport, context: context))
      scene.prepare(viewport: viewport)
      let tree = context.interaction.tree
      let actual = scene.paint()
      #expect(context.interaction.tree === tree)
      context.interaction.beginFrame(input: InputState(), processingInput: false)
      var expected = DrawList()
      BlockEngine.draw(primitive, into: &expected, in: rect, context: context)
      context.interaction.endFrame()
      #expect(actual.commands == expected.commands)
    }
  }

  @Test func animationsReplayWithoutBuildingOrLayingOutAndStopOnReplacement() throws {
    let context = BlockContext()
    let clock = Clock()
    var builds = 0
    let producer = NodeFrameProducer(clock: { clock.now })
    let content = DeferredBlock {
      builds += 1
      return VStack {
        ProgressIndicator()
        MarqueeText("A long scrolling label")
      }
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let first = producer.paint()
    #expect(producer.needsAnimationFrame)
    let layouts = producer.layouts
    let preparations = producer.preparations
    clock.now = 1.4
    #expect(producer.renderAnimations().commands != first.commands)
    #expect(builds == 1)
    #expect(producer.layouts == layouts)
    #expect(producer.preparations == preparations)
    producer.reset()
    try producer.refresh(
      content: ProgressIndicator(isActive: false), viewport: viewport, context: context, onChange: {})
    _ = producer.paint()
    #expect(!producer.needsAnimationFrame)
    producer.reset()
    try producer.refresh(content: MarqueeText("Short"), viewport: viewport, context: context, onChange: {})
    _ = producer.paint()
    #expect(!producer.needsAnimationFrame)
    producer.reset()
    #expect(producer.renderAnimations().commands.isEmpty)
  }

  @Test func cullingPreservesProgressDotsOverflowingTheirAssignedHeight() throws {
    let scene = NodeScene()
    let context = BlockContext()
    try scene.update(ProgressIndicator(diameter: 18), context: context)
    try scene.layout(in: Rect(x: 0, y: 10, width: 18, height: 0))
    scene.prepare(viewport: Size(width: 20, height: 5))
    #expect(scene.paint().commands == scene.paint(cullingEnabled: false).commands)
    #expect(!scene.paint().commands.isEmpty)
  }

  @Test func replacingImagePixelsReusesLayoutAndKeepsSubmittedResourcesOwned() throws {
    let resource = try ImageResource(id: ImageID("pixel"), width: 1, height: 1, rgba8: Data([255, 0, 0, 255]))
    let replacement = try resource.replacingPixels(width: 1, height: 1, rgba8: Data([0, 255, 0, 255]))
    let scene = NodeScene()
    let context = BlockContext()
    let rect = Rect(origin: .zero, size: viewport)
    try scene.update(Image(resource), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: viewport)
    let first = scene.paint()
    let layouts = scene.layouts
    try scene.update(Image(replacement), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: viewport)
    let second = scene.paint()
    #expect(scene.layouts == layouts)
    #expect(first.commands != second.commands)
    guard case .image(_, let retained, _, _) = first.commands.first else {
      Issue.record("Expected image command")
      return
    }
    #expect(retained == resource)
  }
}
