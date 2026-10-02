import Chroma
import ChromaTesting
import Foundation

/// A request/response JSONL transport for the same App and input engine used by native hosts.
/// It produces draw commands, not raster images. See Documentation/HeadlessAgents.md.
@MainActor
public final class HeadlessSession {
  public let host: HeadlessHost
  public private(set) var isClosed = false
  private var pointer = Point.zero
  private var press = Point.zero
  private var pointerDown = false

  public init<A: App>(_ app: A, viewport: Size? = nil) throws {
    let size = viewport ?? app.windowSize
    guard Self.validViewport(size) else { throw Failure.invalidViewport }
    host = HeadlessHost(size: size)
    try host.launch(app)
    host.onClose = { [weak self] in self?.isClosed = true }
  }

  /// One response per request, including invalid requests. Invalid input never mutates the app.
  public func respond(to line: String) -> String {
    var id: String?
    do {
      guard line.utf8.count <= Self.maximumLineBytes else { throw Failure.lineTooLong }
      // Recover correlation even when another field has an invalid type.
      id = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? String
      if let value = id, value.utf8.count > 256 {
        id = nil
        throw Failure.invalidRequest
      }
      let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
      id = request.id
      if let value = id, value.utf8.count > 256 {
        id = nil
        throw Failure.invalidRequest
      }
      guard request.version == 1 else { throw Failure.unsupportedVersion }
      guard !isClosed else { throw Failure.closed }
      guard (request.text?.utf8.count ?? 0) <= 16_384 else { throw Failure.invalidRequest }
      var input = InputState(pointerPosition: pointer, pointerPressPosition: press, pointerDown: pointerDown)
      switch request.op {
      case "frame": break
      case "key":
        let modifiers = try Self.modifiers(request.modifiers ?? [])
        let key = try request.key.map(Self.key)
        guard key != nil || request.text != nil else { throw Failure.invalidRequest }
        let resolved = host.resolve(
          KeyboardInput(chord: key.map { KeyChord($0, modifiers: modifiers) }, text: request.text))
        switch resolved {
        case .command(let command): input.commands = [command]
        case .text(let event): input.textEvents = [event]
        case nil: break
        }
        host.sendInput(input)
      case "pointer":
        guard let x = request.x, let y = request.y,
          Self.validCoordinate(x), Self.validCoordinate(y), let phase = request.phase,
          ["move", "down", "up"].contains(phase)
        else { throw Failure.invalidRequest }
        guard !(phase == "down" && pointerDown), !(phase == "up" && !pointerDown)
        else { throw Failure.invalidPointerTransition }
        pointer = Point(x: x, y: y)
        if phase == "down" {
          press = pointer
          pointerDown = true
        }
        if phase == "up" { pointerDown = false }
        input = InputState(
          pointerPosition: pointer, pointerPressPosition: press,
          pointerDown: pointerDown, pointerPressed: phase == "down", pointerReleased: phase == "up")
        host.sendInput(input)
      case "scroll":
        guard let x = request.x, let y = request.y, Self.validCoordinate(x), Self.validCoordinate(y) else {
          throw Failure.invalidRequest
        }
        input.scrollDelta = Point(x: x, y: y)
        host.sendInput(input)
      case "resize":
        guard let width = request.width, let height = request.height,
          Self.validViewport(Size(width: width, height: height))
        else { throw Failure.invalidViewport }
        host.viewport = Size(width: width, height: height)
      case "quit":
        close()
        return encode(Response(id: id, status: "closed"))
      default: throw Failure.unknownOperation
      }
      // Explicit snapshots are deterministic request boundaries, not a promise that all
      // background app work has finished. Never replay transient events while painting.
      let frame = host.render(
        input: InputState(pointerPosition: pointer, pointerPressPosition: press, pointerDown: pointerDown))
      return encode(
        Response(
          id: id, status: "frame", viewport: frame.viewport, commands: frame.commands,
          focus: Focus(
            path: host.interaction.selection, editing: host.interaction.isTextEditing,
            caretOffset: host.interaction.editingLeaf == nil ? nil : host.interaction.caretOffset,
            selectionStart: host.interaction.textSelectionRange?.lowerBound,
            selectionEnd: host.interaction.textSelectionRange?.upperBound)))
    } catch let failure as Failure {
      return encode(Response(id: id, status: "error", error: failure.rawValue))
    } catch {
      return encode(Response(id: id, status: "error", error: "invalid_request"))
    }
  }

  public func close() {
    guard !isClosed else { return }
    isClosed = true
    host.close()
  }

  /// Serves stdin until EOF or quit. No timers, unsolicited frames, or window connection.
  /// Reading off the main actor lets the application's asynchronous work continue while idle.
  public func runStandardIO() async throws {
    let channels = try StandardIOChannels()
    defer { withExtendedLifetime(channels) {} }
    try await runStandardIO(output: channels.output)
  }

  func runStandardIO(output: FileHandle) async throws {
    defer { close() }
    let reader = BoundedLineReader(handle: .standardInput, limit: Self.maximumLineBytes)
    while !isClosed, let line = try await Task.detached(operation: { try reader.next() }).value {
      let response: String
      switch line {
      case .bytes(let data):
        if let string = String(data: data, encoding: .utf8) {
          response = respond(to: string)
        } else {
          response = encode(Response(status: "error", error: "invalid_utf8"))
        }
      case .oversized:
        response = encode(Response(status: "error", error: "line_too_long"))
      }
      try output.write(contentsOf: Data((response + "\n").utf8))
      if let object = try? JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any],
        let error = object["error"] as? String
      {
        try FileHandle.standardError.write(contentsOf: Data(("chroma-headless: " + error + "\n").utf8))
      }
    }
  }

  public static let maximumLineBytes = 65_536

  private static func validViewport(_ size: Size) -> Bool {
    size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
      && size.width <= 16_384 && size.height <= 16_384
  }

  private static func validCoordinate(_ value: Float) -> Bool {
    value.isFinite && abs(value) <= 1_000_000
  }

  private func encode(_ response: Response) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      return String(decoding: try encoder.encode(response), as: UTF8.self)
    } catch {
      // App-produced invalid geometry must not corrupt the JSONL stream.
      let fallback = Response(id: response.id, status: "error", error: "unencodable_frame")
      return String(decoding: try! encoder.encode(fallback), as: UTF8.self)
    }
  }

  private static func key(_ value: String) throws -> Key {
    switch value {
    case "up": return .upArrow
    case "down": return .downArrow
    case "left": return .leftArrow
    case "right": return .rightArrow
    case "tab": return .tab
    case "enter": return .enter
    case "escape": return .escape
    case "space": return .space
    case "home": return .home
    case "end": return .end
    case "pageUp": return .pageUp
    case "pageDown": return .pageDown
    case "delete": return .delete
    case "backspace": return .backspace
    default:
      if value.count == 1, let character = value.first { return .character(character) }
      throw Failure.invalidRequest
    }
  }

  private static func modifiers(_ values: [String]) throws -> KeyModifiers {
    var result: KeyModifiers = []
    for value in values {
      switch value {
      case "shift": result.insert(.shift)
      case "control": result.insert(.control)
      case "option": result.insert(.option)
      case "command": result.insert(.command)
      case "super": result.insert(.superKey)
      default: throw Failure.invalidRequest
      }
    }
    return result
  }

  private enum Failure: String, Error, CustomStringConvertible {
    case invalidViewport = "invalid_viewport"
    case lineTooLong = "line_too_long"
    case invalidRequest = "invalid_request"
    case unsupportedVersion = "unsupported_version"
    case unknownOperation = "unknown_operation"
    case invalidPointerTransition = "invalid_pointer_transition"
    case closed

    var description: String {
      self == .invalidViewport ? "viewport dimensions must be finite and within 1...16384" : rawValue
    }
  }

  private struct Request: Decodable {
    let version: Int
    let id: String?
    let op: String
    let key: String?
    let modifiers: [String]?
    let text: String?
    let x: Float?
    let y: Float?
    let phase: String?
    let width: Float?
    let height: Float?
  }

  private struct Focus: Encodable {
    let path: [Int]?
    let editing: Bool
    let caretOffset: Int?
    let selectionStart: Int?
    let selectionEnd: Int?
  }

  private struct Response: Encodable {
    let version = 1
    var id: String?
    let status: String
    var viewport: Size?
    var commands: [DrawCommand]?
    var focus: Focus?
    var error: String?
  }
}
