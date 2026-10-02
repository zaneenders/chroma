import Chroma
import Foundation
import Observation
import Testing

@testable import ChromaHeadless

@MainActor struct HeadlessSessionTests {
  struct Fixture: App { var body: some Block { Text("Hello") } }

  private func response(_ session: HeadlessSession, _ request: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(session.respond(to: request).utf8)) as? [String: Any])
  }

  @Test func validationAndCorrelation() throws {
    let session = try HeadlessSession(Fixture())
    let invalid = try response(session, #"{"version":1,"id":"test","op":"resize","width":0,"height":100}"#)
    #expect(invalid["error"] as? String == "invalid_viewport")
    #expect(invalid["id"] as? String == "test")
    #expect(session.host.viewport == Size(width: 800, height: 600))
    #expect(session.respond(to: #"{"version":1,"op":"frame"}"#).contains("Hello"))
    let mistyped = try response(session, #"{"version":"wrong","id":"kept","op":"frame"}"#)
    #expect(mistyped["id"] as? String == "kept")
    #expect(mistyped["error"] as? String == "invalid_request")
  }

  @Test func duplicateIDsCannotBypassLengthLimit() throws {
    let session = try HeadlessSession(Fixture())
    let longID = String(repeating: "a", count: 257)
    let result = try response(session, "{\"version\":1,\"op\":\"frame\",\"id\":\"\(longID)\",\"id\":\"small\"}")
    #expect(result["error"] as? String == "invalid_request")
    #expect(result["id"] == nil)
  }

  @Test func viewportLimits() throws {
    for size in [Size(width: .nan, height: 20), Size(width: .infinity, height: 20), Size(width: 16_385, height: 20)] {
      #expect(throws: (any Error).self) { try HeadlessSession(Fixture(), viewport: size) }
    }
    let session = try HeadlessSession(Fixture(), viewport: Size(width: 1, height: 16_384))
    #expect(session.host.viewport == Size(width: 1, height: 16_384))
  }

  @Test func invalidInputDoesNotMutateFrame() throws {
    let session = try HeadlessSession(Fixture())
    let initial = session.respond(to: #"{"version":1,"op":"frame"}"#)
    for request in [
      #"{"version":2,"op":"frame"}"#,
      #"{"version":1,"op":"invalid"}"#,
      #"{"version":1,"op":"pointer","phase":"up","x":0,"y":0}"#,
      #"{"version":1,"op":"pointer","phase":"down","x":1e20,"y":0}"#,
      #"{"version":1,"op":"key","key":"unknown"}"#,
      #"{"version":1,"op":"key","key":"enter","modifiers":["invalid"]}"#,
      #"{"version":1,"op":"resize","width":1e100,"height":20}"#,
      "{", String(repeating: "x", count: 65_537),
    ] {
      #expect(try response(session, request)["status"] as? String == "error")
      #expect(session.respond(to: #"{"version":1,"op":"frame"}"#) == initial)
    }
  }

  @Test func pointerTransitionsAndClose() throws {
    let session = try HeadlessSession(Fixture())
    let down = #"{"version":1,"op":"pointer","phase":"down","x":20,"y":20}"#
    #expect(try response(session, down)["status"] as? String == "frame")
    #expect(try response(session, down)["error"] as? String == "invalid_pointer_transition")
    #expect(
      try response(session, #"{"version":1,"op":"pointer","phase":"up","x":20,"y":20}"#)["status"] as? String == "frame"
    )
    #expect(try response(session, #"{"version":1,"id":"bye","op":"quit"}"#)["status"] as? String == "closed")
    #expect(session.isClosed)
    session.close()
    #expect(try response(session, #"{"version":1,"op":"frame"}"#)["error"] as? String == "closed")
  }

  @Observable final class EditorModel { var text = "" }
  struct EditorApp: App {
    let model = EditorModel()
    var keyBindings: KeyBindings { .desktopNavigation }
    var body: some Block {
      TextEditor("Edit", singleLine: true, text: { model.text }, onChange: { model.text = $0 })
    }
  }

  @Test func escapeReportsMovementAndDoesNotInsertText() throws {
    let app = EditorApp()
    let session = try HeadlessSession(app)
    _ = session.respond(to: #"{"version":1,"op":"key","key":"tab"}"#)
    _ = session.respond(to: #"{"version":1,"op":"key","key":"enter"}"#)
    _ = session.respond(to: #"{"version":1,"op":"key","text":"hello"}"#)
    #expect(app.model.text == "hello")
    let escaped = try response(session, #"{"version":1,"op":"key","key":"escape"}"#)
    let focus = try #require(escaped["focus"] as? [String: Any])
    #expect(focus["editing"] as? Bool == false)
    _ = session.respond(to: #"{"version":1,"op":"key","text":"ignored"}"#)
    #expect(app.model.text == "hello")
  }

  struct InvalidGeometry: PrimitiveBlock {
    var focusRule: FocusRule { .standard }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      list.fillRect(Rect(x: .nan, y: 0, width: 10, height: 10), color: Color(r: 1, g: 0, b: 0, a: 1))
    }
  }
  struct InvalidApp: App { var body: some Block { InvalidGeometry() } }

  @Test func unencodableAppGeometryReturnsAnError() throws {
    let session = try HeadlessSession(InvalidApp())
    #expect(
      try response(session, #"{"version":1,"id":"bad-frame","op":"frame"}"#)["error"] as? String == "unencodable_frame")
  }
}
