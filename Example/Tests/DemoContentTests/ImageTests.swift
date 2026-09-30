import Chroma
import ChromaTesting
import Testing

@testable import DemoContent

@MainActor
struct ImageTests {
  @Test func imageScreenEmitsMandelbrotImage() throws {
    let state = DemoState(automaticallyUpdates: false)
    state.open(.image)
    let host = HeadlessHost(size: Size(width: 1120, height: 840))
    host.content = DemoApplication(state: state, shortcutModifier: .command).body
    let images = host.render().commands.compactMap { command -> ImageResource? in
      if case .image(_, let image, .contain, _) = command { return image }
      return nil
    }
    let image = try #require(images.first)
    #expect(images.count == 1)
    #expect(image.id == ImageID("demo.mandelbrot"))
    #expect(image.width == 640)
    #expect(image.height == 400)
  }
}
