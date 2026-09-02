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

  @Test func contentModesResolveCenteredGeometry() {
    let destination = Rect(x: 10, y: 20, width: 100, height: 100)
    let source = Size(width: 200, height: 100)

    #expect(ImageContentMode.stretch.drawRect(sourceSize: source, in: destination) == destination)
    #expect(
      ImageContentMode.aspectFit.drawRect(sourceSize: source, in: destination)
        == Rect(x: 10, y: 45, width: 100, height: 50))
    #expect(
      ImageContentMode.aspectFill.drawRect(sourceSize: source, in: destination)
        == Rect(x: -40, y: 20, width: 200, height: 100))
    #expect(
      ImageContentMode.aspectFit.drawRect(sourceSize: source, in: .zero) == nil)
  }

  @Test func imageBlockEmitsDeterministicHeadlessCommand() throws {
    let image = try resource()
    let renderer = HeadlessRenderer(size: Size(width: 120, height: 80))
    renderer.content = Image(image, contentMode: .aspectFit)

    let first = renderer.render()
    let second = renderer.render()

    #expect(first == second)
    #expect(
      first.commands == [
        .image(
          rect: Rect(x: 0, y: 0, width: 120, height: 80),
          image: image,
          contentMode: .aspectFit)
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
