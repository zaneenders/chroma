import AppKit
import Chroma
import Testing

@testable import MetalBackend

@Suite @MainActor
struct InputViewTests {
  private func wheel(at location: CGPoint, x: Int32 = 3, y: Int32 = -7) throws -> NSEvent {
    let event = try #require(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: y, wheel2: x, wheel3: 0))
    event.location = location
    return try #require(NSEvent(cgEvent: event))
  }

  private func position(of event: NSEvent, in view: ChromaInputView) -> Point {
    let location = view.convert(event.locationInWindow, from: nil)
    return Point(x: Float(location.x), y: Float(view.bounds.height - location.y))
  }

  @Test func wheelUpdatesPointerWithoutAnEarlierMouseMove() throws {
    let view = ChromaInputView(frame: CGRect(x: 0, y: 0, width: 200, height: 100), device: nil)
    let event = try wheel(at: CGPoint(x: 40, y: 30))
    let expected = position(of: event, in: view)
    #expect(expected != Point(x: -1, y: -1))
    var delivered: InputState?
    view.onInputAvailable = { [weak view] in delivered = view?.frameInput() }

    view.scrollWheel(with: event)

    let input = try #require(delivered)
    #expect(input.pointerPosition == expected)
    #expect(input.scrollDelta == Point(x: Float(event.scrollingDeltaX), y: Float(event.scrollingDeltaY)))
    #expect(!input.pointerDown && !input.pointerPressed && !input.pointerReleased)
    #expect(view.frameInput().scrollDelta == .zero)
  }

  @Test func wheelReplacesStalePointerAndPreservesAccumulatedDeltas() throws {
    let view = ChromaInputView(frame: CGRect(x: 0, y: 0, width: 200, height: 100), device: nil)
    let first = try wheel(at: CGPoint(x: 20, y: 10))
    let second = try wheel(at: CGPoint(x: 140, y: 70), x: -2, y: -5)
    view.mouseMoved(with: first)
    #expect(view.frameInput().pointerPosition != position(of: second, in: view))

    view.scrollWheel(with: first)
    view.scrollWheel(with: second)

    let input = view.frameInput()
    #expect(input.pointerPosition == position(of: second, in: view))
    #expect(
      input.scrollDelta
        == Point(
          x: Float(first.scrollingDeltaX) + Float(second.scrollingDeltaX),
          y: Float(first.scrollingDeltaY) + Float(second.scrollingDeltaY)))
    let next = view.frameInput()
    #expect(next.pointerPosition == input.pointerPosition)
    #expect(next.scrollDelta == .zero)
  }

  @Test func wheelRefreshesPointerAfterExit() throws {
    let view = ChromaInputView(frame: CGRect(x: 0, y: 0, width: 200, height: 100), device: nil)
    let event = try wheel(at: CGPoint(x: 70, y: 50))
    view.mouseExited(with: event)
    #expect(view.frameInput().pointerPosition == Point(x: -1, y: -1))

    view.scrollWheel(with: event)

    #expect(view.frameInput().pointerPosition == position(of: event, in: view))
  }
}
