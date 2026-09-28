import Foundation
import HeadlessBackend
import Testing

@testable import Chroma

@MainActor
struct ImageRenderingTests {
  private func resource(
    id: String = "test", generation: UInt64 = 0, width: Int = 2, height: Int = 1
  ) throws -> ImageResource {
    try ImageResource(
      id: ImageID(id), generation: generation, width: width, height: height,
      rgba8: Data(repeating: 255, count: width * height * 4))
  }

  @Test func validatesDimensionsAndPixelCount() throws {
    #expect(throws: ImageResourceError.invalidDimensions(width: 0, height: 2)) {
      try ImageResource(id: ImageID("bad"), width: 0, height: 2, rgba8: Data())
    }
    #expect(throws: ImageResourceError.invalidByteCount(expected: 8, actual: 7)) {
      try ImageResource(id: ImageID("bad"), width: 2, height: 1, rgba8: Data(repeating: 0, count: 7))
    }
    #expect(throws: ImageResourceError.pixelCountOverflow) {
      try ImageResource(id: ImageID("huge"), width: Int.max, height: 2, rgba8: Data())
    }
  }

  @Test func replacingPixelsPreservesIdentityAndIncrementsGeneration() throws {
    let original = try resource(generation: 41)
    let pixels = Data(repeating: 7, count: 3 * 2 * 4)

    let replacement = try original.replacingPixels(width: 3, height: 2, rgba8: pixels)

    #expect(replacement.id == original.id)
    #expect(replacement.generation == 42)
    #expect(replacement.width == 3)
    #expect(replacement.height == 2)
    #expect(replacement.rgba8 == pixels)
    #expect(original.generation == 41)
    #expect(original.width == 2)
    #expect(original.height == 1)
  }

  @Test func replacingPixelsValidatesBeforeReturningReplacement() throws {
    let original = try resource()

    #expect(throws: ImageResourceError.invalidDimensions(width: 0, height: 1)) {
      try original.replacingPixels(width: 0, height: 1, rgba8: Data())
    }
    #expect(throws: ImageResourceError.invalidByteCount(expected: 8, actual: 7)) {
      try original.replacingPixels(
        width: 2, height: 1, rgba8: Data(repeating: 0, count: 7))
    }
  }

  @Test func replacingPixelsRejectsGenerationOverflow() throws {
    let image = try resource(generation: .max)

    #expect(throws: ImageResourceError.generationOverflow) {
      try image.replacingPixels(width: 2, height: 1, rgba8: image.rgba8)
    }
  }

  @Test func scalingModesResolveCenteredGeometry() {
    let destination = Rect(x: 10, y: 20, width: 100, height: 100)
    let source = Size(width: 200, height: 100)

    #expect(ImageScaling.stretch.drawRect(sourceSize: source, in: destination) == destination)
    #expect(
      ImageScaling.contain.drawRect(sourceSize: source, in: destination)
        == Rect(x: 10, y: 45, width: 100, height: 50))
    #expect(
      ImageScaling.cover.drawRect(sourceSize: source, in: destination)
        == Rect(x: -40, y: 20, width: 200, height: 100))
    #expect(ImageScaling.contain.drawRect(sourceSize: source, in: .zero) == nil)
  }

  @Test func alignmentPositionsContainedImageInUnusedSpace() {
    let destination = Rect(x: 10, y: 20, width: 100, height: 100)
    let source = Size(width: 200, height: 100)

    #expect(
      ImageScaling.contain.drawRect(
        sourceSize: source, in: destination, alignment: .topLeading)
        == Rect(x: 10, y: 20, width: 100, height: 50))
    #expect(
      ImageScaling.contain.drawRect(
        sourceSize: source, in: destination, alignment: .bottomTrailing)
        == Rect(x: 10, y: 70, width: 100, height: 50))
  }

  @Test func alignmentSelectsTheRegionPreservedByCover() {
    let destination = Rect(x: 10, y: 20, width: 100, height: 100)
    let source = Size(width: 200, height: 100)

    #expect(
      ImageScaling.cover.drawRect(
        sourceSize: source, in: destination, alignment: .leading)
        == Rect(x: 10, y: 20, width: 200, height: 100))
    #expect(
      ImageScaling.cover.drawRect(
        sourceSize: source, in: destination, alignment: .trailing)
        == Rect(x: -90, y: 20, width: 200, height: 100))
  }

  @Test func customAlignmentIsClampedAndNonFiniteValuesCenter() {
    #expect(ImageAlignment(x: -2, y: 3) == .bottomLeading)
    #expect(ImageAlignment(x: .infinity, y: .nan) == .center)
  }

  @Test func imageUsesIntrinsicSizeWithoutImplicitExpansion() throws {
    let image = Image(try resource(width: 80, height: 40))
    let proposal = Size(width: 300, height: 200)
    let context = RenderContext()

    #expect(BlockEngine.measure(image, proposal: proposal, context: context) == image.resource.size)
    #expect(BlockEngine.measure(image.sizing(), proposal: proposal, context: context) == image.resource.size)
    #expect(!BlockEngine.expandsHorizontally(image))
    #expect(!BlockEngine.expandsVertically(image))
  }

  @Test func imageCanOptIntoExpansionIndependentlyOnEachAxis() throws {
    let image = Image(try resource(width: 80, height: 40))
    let proposal = Size(width: 300, height: 200)
    let context = RenderContext()
    let horizontal = image.sizing(x: .grow)
    let vertical = image.sizing(y: .grow)

    #expect(BlockEngine.measure(horizontal, proposal: proposal, context: context) == Size(width: 300, height: 40))
    #expect(BlockEngine.expandsHorizontally(horizontal))
    #expect(!BlockEngine.expandsVertically(horizontal))
    #expect(BlockEngine.measure(vertical, proposal: proposal, context: context) == Size(width: 80, height: 200))
    #expect(!BlockEngine.expandsHorizontally(vertical))
    #expect(BlockEngine.expandsVertically(vertical))
  }

  @Test func imageInStackKeepsIntrinsicSize() throws {
    let image = try resource(width: 80, height: 40)
    let stack = HStack(spacing: 5) {
      Image(image)
      Image(image)
    }
    let context = RenderContext()

    #expect(
      BlockEngine.measure(
        stack, proposal: Size(width: 300, height: 200), context: context)
        == Size(width: 165, height: 40))
  }

  @Test func imageInFixedFrameUsesAssignedRectForEveryScalingMode() throws {
    let resource = try resource(width: 80, height: 40)
    let frame = Rect(x: 0, y: 0, width: 100, height: 100)
    let context = RenderContext()

    for scaling in [ImageScaling.contain, .cover, .stretch] {
      let image = Image(resource, scaling: scaling).sizing(
        x: .fixed(frame.size.width), y: .fixed(frame.size.height))
      var list = DrawList()
      BlockEngine.draw(image, into: &list, in: frame, context: context)

      #expect(
        list.commands == [
          .image(rect: frame, image: resource, scaling: scaling, alignment: .center)
        ])
    }
  }

  @Test func imageInScrollViewUsesIntrinsicContentSize() throws {
    let resource = try resource(width: 80, height: 40)
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let viewport = Rect(x: 0, y: 0, width: 100, height: 20)
    interaction.beginFrame(input: InputState())
    var list = DrawList()

    BlockEngine.draw(
      ScrollView(id: WidgetID("image-scroll"), showsIndicator: false) {
        Image(resource)
      },
      into: &list,
      in: viewport,
      context: context
    )
    interaction.endFrame()

    #expect(interaction.scrollLimit(for: WidgetID("image-scroll")) == 20)
    #expect(interaction.horizontalScrollLimit(for: WidgetID("image-scroll")) == 0)
    #expect(
      list.commands == [
        .pushClip(viewport),
        .image(
          rect: Rect(x: 0, y: 0, width: 80, height: 40), image: resource,
          scaling: .contain, alignment: .center),
        .popClip,
      ])
  }

  @Test func imageBlockEmitsDeterministicHeadlessCommand() throws {
    let image = try resource()
    let renderer = HeadlessRenderer(size: Size(width: 120, height: 80))
    renderer.content = Image(image, scaling: .cover, alignment: .top)
      .sizing(x: .grow, y: .grow)

    let first = renderer.render()
    let second = renderer.render()

    #expect(first == second)
    #expect(
      first.commands == [
        .image(
          rect: Rect(x: 0, y: 0, width: 120, height: 80),
          image: image,
          scaling: .cover,
          alignment: .top),
        .fillRect(
          rect: Rect(x: 0, y: 0, width: 120, height: 80),
          color: HoverStyle.standardTint(in: .dark)),
        .strokeRoundedRect(
          rect: Rect(x: 0, y: 0, width: 120, height: 80),
          radii: CornerRadii(5), width: 1, color: ChromaTheme.dark.border),
      ])
  }

  @Test func imageDefaultsToContainAndCenter() throws {
    let image = try resource()
    var list = DrawList()
    list.image(image, in: Rect(x: 1, y: 2, width: 3, height: 4))

    #expect(
      list.commands == [
        .image(
          rect: Rect(x: 1, y: 2, width: 3, height: 4),
          image: image,
          scaling: .contain,
          alignment: .center)
      ])
  }

  @Test func identityAndGenerationParticipateInEquality() throws {
    let original = try resource()
    let same = try resource()
    let newer = try resource(generation: 1)
    let other = try resource(id: "other")

    #expect(original == same)
    #expect(original != newer)
    #expect(original != other)
  }
}
