import Chroma
import ChromaHeadless
import Foundation
import Observation
import Testing

@MainActor struct HeadlessSessionTests {
  struct Fixture: App { var body: some Block { Text("Hello") } }

  private func response(_ session: HeadlessSession, _ request: String) throws -> HeadlessResponse {
    try JSONDecoder().decode(HeadlessResponse.self, from: Data(session.respond(to: request).utf8))
  }

  @Test func sharedProtocolTypes() throws {
    let session = try HeadlessSession(Fixture())
    defer { session.close() }
    let request = HeadlessRequest(id: "frame-1", op: .frame)
    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(HeadlessRequest.self, from: data)
    #expect(decoded.version == 1)
    #expect(decoded.id == "frame-1")
    #expect(decoded.op == .frame)
    let frame = try response(session, String(decoding: data, as: UTF8.self))
    #expect(frame.version == 1)
    #expect(frame.id == request.id)
    #expect(frame.status == .frame)
    #expect(frame.viewport == session.host.viewport)
    #expect(frame.commands?.isEmpty == false)
    #expect(frame.focus != nil)
    let roundTrip = try JSONDecoder().decode(HeadlessResponse.self, from: JSONEncoder().encode(frame))
    #expect(roundTrip.commands == frame.commands)
    #expect(roundTrip.focus?.editing == frame.focus?.editing)
  }

  @Test func typedWireValuesKeepTheirJSONRepresentation() throws {
    let request = HeadlessRequest(
      id: "still-alive\u{2028}\u{2029}\u{85}", op: .key,
      key: .character("é"), modifiers: [.shift, .super], phase: .down)
    let data = try JSONEncoder().encode(request)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["id"] as? String == request.id?.rawValue)
    #expect(json["op"] as? String == "key")
    #expect(json["key"] as? String == "é")
    #expect(json["modifiers"] as? [String] == ["shift", "super"])
    #expect(json["phase"] as? String == "down")
    let decoded = try JSONDecoder().decode(HeadlessRequest.self, from: data)
    #expect(decoded.id == request.id)
    #expect(decoded.key == request.key)
    #expect(decoded.modifiers == request.modifiers)
    for key in [HeadlessKey.tab, .pageUp, .character("🦊")] {
      #expect(try JSONDecoder().decode(HeadlessKey.self, from: JSONEncoder().encode(key)) == key)
    }
    let session = try HeadlessSession(Fixture())
    defer { session.close() }
    #expect(try response(session, #"{"version":1,"id":"unknown","op":"unknown"}"#).error == .unknownOperation)
    #expect(
      try response(session, #"{"version":1,"op":"pointer","phase":"invalid","x":0,"y":0}"#).error == .invalidRequest)
  }

  @Test func validationAndCorrelation() throws {
    let session = try HeadlessSession(Fixture())
    let invalid = try response(session, #"{"version":1,"id":"test","op":"resize","width":0,"height":100}"#)
    #expect(invalid.error == .invalidViewport)
    #expect(invalid.id == "test")
    #expect(session.host.viewport == Size(width: 800, height: 600))
    #expect(session.respond(to: #"{"version":1,"op":"frame"}"#).contains("Hello"))
    let mistyped = try response(session, #"{"version":"wrong","id":"kept","op":"frame"}"#)
    #expect(mistyped.id == "kept")
    #expect(mistyped.error == .invalidRequest)
  }

  @Test func duplicateIDsCannotBypassLengthLimit() throws {
    let session = try HeadlessSession(Fixture())
    let longID = String(repeating: "a", count: 257)
    let result = try response(session, "{\"version\":1,\"op\":\"frame\",\"id\":\"\(longID)\",\"id\":\"small\"}")
    #expect(result.error == .invalidRequest)
    #expect(result.id == nil)
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
      #expect(try response(session, request).status == .error)
      #expect(session.respond(to: #"{"version":1,"op":"frame"}"#) == initial)
    }
  }

  @Test func pointerTransitionsAndClose() throws {
    let session = try HeadlessSession(Fixture())
    let down = #"{"version":1,"op":"pointer","phase":"down","x":20,"y":20}"#
    #expect(try response(session, down).status == .frame)
    #expect(try response(session, down).error == .invalidPointerTransition)
    #expect(
      try response(session, #"{"version":1,"op":"pointer","phase":"up","x":20,"y":20}"#).status == .frame
    )
    #expect(try response(session, #"{"version":1,"id":"bye","op":"quit"}"#).status == .closed)
    #expect(session.isClosed)
    session.close()
    #expect(try response(session, #"{"version":1,"op":"frame"}"#).error == .closed)
  }

  @Observable final class EditorModel { var text = "" }
  struct EditorApp: App {
    let model = EditorModel()
    var keyBindings: KeyBindings { .desktopNavigation }
    var body: some Block {
      TextEditor("Edit", singleLine: true, text: { model.text }, onChange: { model.text = $0 })
    }
  }

  @Observable final class TimerModel { var tick = 0 }
  struct TimerApp: App {
    let model = TimerModel()
    var body: some Block { Text("Tick: \(model.tick)") }
  }

  @Test func asyncTimerUpdatesAppearInFrameSnapshots() async throws {
    let app = TimerApp()
    let model = app.model
    let session = try HeadlessSession(app)
    defer { session.close() }
    func texts(_ frame: HeadlessResponse) -> [String] {
      (frame.commands ?? []).compactMap { command in
        guard case .text(_, let text, _, _) = command else { return nil }
        return text
      }
    }
    let initial = try response(session, #"{"version":1,"op":"frame"}"#)
    #expect(texts(initial) == ["Tick: 0"])
    // A separate main-actor task suspends between ticks, just like an app timer.
    let timer = Task { @MainActor in
      for tick in 1...3 {
        try await Task.sleep(for: .milliseconds(50))
        model.tick = tick
        let frame = try response(session, #"{"version":1,"op":"frame"}"#)
        #expect(frame.status == .frame)
        #expect(texts(frame) == ["Tick: \(tick)"])
        #expect(frame.commands != initial.commands)
      }
    }
    defer { timer.cancel() }
    try await timer.value
    let final = try response(session, #"{"version":1,"op":"frame"}"#)
    #expect(texts(final) == ["Tick: 3"])
    #expect(try response(session, #"{"version":1,"op":"frame"}"#).commands == final.commands)
  }

  @Test func escapeReportsMovementAndDoesNotInsertText() throws {
    let app = EditorApp()
    let session = try HeadlessSession(app)
    _ = session.respond(to: #"{"version":1,"op":"key","key":"tab"}"#)
    _ = session.respond(to: #"{"version":1,"op":"key","key":"enter"}"#)
    _ = session.respond(to: #"{"version":1,"op":"key","text":"hello"}"#)
    #expect(app.model.text == "hello")
    let escaped = try response(session, #"{"version":1,"op":"key","key":"escape"}"#)
    let focus = try #require(escaped.focus)
    #expect(focus.editing == false)
    _ = session.respond(to: #"{"version":1,"op":"key","text":"ignored"}"#)
    #expect(app.model.text == "hello")
  }

  struct InvalidGeometry: PaintableBlock {
    var focusRule: FocusRule { .standard }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func register(in rect: Rect, context: BlockContext) {}
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      list.fillRect(Rect(x: .nan, y: 0, width: 10, height: 10), color: Color(r: 1, g: 0, b: 0, a: 1))
    }
  }
  struct InvalidApp: App { var body: some Block { InvalidGeometry() } }

  @Test func unencodableAppGeometryReturnsAnError() throws {
    let session = try HeadlessSession(InvalidApp())
    #expect(
      try response(session, #"{"version":1,"id":"bad-frame","op":"frame"}"#).error == .unencodableFrame)
  }
}
