import Chroma
import Testing

@Suite("Cross-platform notification banner")
@MainActor
struct NotificationBannerTests {
  let viewport = Size(width: 800, height: 600)

  @Test func rendersWithoutRemoteFrameAndDismissesLocally() {
    let banner = NotificationBanner()
    #expect(banner.render(viewport: viewport).commands.isEmpty)
    banner.show("Disconnected")
    #expect(!banner.render(viewport: viewport).commands.isEmpty)
    let rect = banner.bounds(in: viewport)
    let point = Point(x: rect.maxX - 26, y: rect.minY + 26)
    #expect(
      banner.handleInput(
        InputState(
          pointerPosition: point, pointerPressPosition: point,
          pointerDown: true, pointerPressed: true), viewport: viewport))
    #expect(banner.handleInput(InputState(pointerPosition: point, pointerReleased: true), viewport: viewport))
    #expect(banner.message == nil)
    #expect(banner.render(viewport: viewport).commands.isEmpty)
    banner.show("Paste failed")
    #expect(banner.message == "Paste failed")
  }

  @Test func wrapsAndFitsNarrowViewport() {
    let banner = NotificationBanner()
    banner.show(String(repeating: "Connection lost. ", count: 8))
    let narrow = banner.bounds(in: Size(width: 320, height: 600))
    let wide = banner.bounds(in: viewport)
    #expect(narrow.size.height > wide.size.height)
    #expect(narrow.minX == 16)
    #expect(narrow.maxX == 304)
    #expect(wide.size.width == 560)
  }

  @Test func outsideInputPassesThroughAndCapturedDragDoesNot() {
    let banner = NotificationBanner()
    banner.show("Disconnected")
    _ = banner.render(viewport: viewport)
    let outside = Point(x: 5, y: 500)
    #expect(!banner.handleInput(InputState(pointerPosition: outside), viewport: viewport))
    let inside = Point(x: 150, y: 30)
    #expect(
      banner.handleInput(
        InputState(
          pointerPosition: inside, pointerPressPosition: inside,
          pointerDown: true, pointerPressed: true), viewport: viewport))
    #expect(banner.handleInput(InputState(pointerPosition: outside, pointerReleased: true), viewport: viewport))
    #expect(banner.message != nil)
    #expect(!banner.handleInput(InputState(pointerPosition: outside), viewport: viewport))
  }

  @Test func automaticDismissalAndReplacement() async throws {
    let banner = NotificationBanner()
    var invalidations = 0
    banner.onChange = { invalidations += 1 }
    banner.show("Reconnected", success: true, dismissAfter: 0.01)
    #expect(banner.success)
    try await Task.sleep(for: .milliseconds(100))
    #expect(banner.message == nil)
    #expect(invalidations == 2)
    banner.show("Reconnected", success: true, dismissAfter: 0.01)
    banner.show("Connection lost")
    try await Task.sleep(for: .milliseconds(100))
    #expect(banner.message == "Connection lost")
    #expect(!banner.success)
  }
}
