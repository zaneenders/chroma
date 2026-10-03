import Chroma
import ChromaTesting
import Foundation

/// A JSONL frame stream and input transport for the same App engine used by native hosts.
/// It produces draw commands, not raster images.
@MainActor
public final class HeadlessSession {
  public let host: HeadlessHost
  public private(set) var isClosed = false
  private var pointer = Point.zero
  private var press = Point.zero
  private var pointerDown = false

  public init<A: App>(_ app: A, viewport: Size? = nil) throws {
    let size = viewport ?? app.windowSize
    guard Self.validViewport(size) else { throw HeadlessError.invalidViewport }
    host = HeadlessHost(size: size)
    try host.launch(app)
    host.onClose = { [weak self] in self?.isClosed = true }
  }

  /// One response per request, including invalid requests. Invalid input never mutates the app.
  public func respond(to line: String) -> String {
    encode(response(to: line)).line
  }

  private func response(to line: String) -> HeadlessResponse {
    var id: String?
    do {
      guard line.utf8.count <= Self.maximumLineBytes else { throw HeadlessError.lineTooLong }
      let data = Data(line.utf8)
      // Recover correlation even when another field has an invalid type.
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      id = object?["id"] as? String
      try Self.validateID(&id)
      if let op = object?["op"] as? String, HeadlessOperation(rawValue: op) == nil,
        let version = object?["version"] as? Int, version == 1, !isClosed
      {
        throw HeadlessError.unknownOperation
      }
      let request = try JSONDecoder().decode(HeadlessRequest.self, from: data)
      id = request.id
      // The decoders may select different values for duplicate JSON fields.
      try Self.validateID(&id)
      guard request.version == 1 else { throw HeadlessError.unsupportedVersion }
      guard !isClosed else { throw HeadlessError.closed }
      guard (request.text?.utf8.count ?? 0) <= 16_384 else { throw HeadlessError.invalidRequest }
      var input = InputState(pointerPosition: pointer, pointerPressPosition: press, pointerDown: pointerDown)
      switch request.op {
      case .frame: break
      case .key:
        let modifiers = Self.modifiers(request.modifiers ?? [])
        let key = request.key.map(Self.key)
        guard key != nil || request.text != nil else { throw HeadlessError.invalidRequest }
        let resolved = host.resolve(
          KeyboardInput(chord: key.map { KeyChord($0, modifiers: modifiers) }, text: request.text))
        switch resolved {
        case .command(let command): input.commands = [command]
        case .text(let event): input.textEvents = [event]
        case nil: break
        }
        host.sendInput(input)
      case .pointer:
        guard let x = request.x, let y = request.y,
          Self.validCoordinate(x), Self.validCoordinate(y), let phase = request.phase
        else { throw HeadlessError.invalidRequest }
        guard !(phase == .down && pointerDown), !(phase == .up && !pointerDown)
        else { throw HeadlessError.invalidPointerTransition }
        pointer = Point(x: x, y: y)
        if phase == .down {
          press = pointer
          pointerDown = true
        }
        if phase == .up { pointerDown = false }
        input = InputState(
          pointerPosition: pointer, pointerPressPosition: press,
          pointerDown: pointerDown, pointerPressed: phase == .down, pointerReleased: phase == .up)
        host.sendInput(input)
      case .scroll:
        guard let x = request.x, let y = request.y, Self.validCoordinate(x), Self.validCoordinate(y) else {
          throw HeadlessError.invalidRequest
        }
        input.scrollDelta = Point(x: x, y: y)
        host.sendInput(input)
      case .resize:
        guard let width = request.width, let height = request.height,
          Self.validViewport(Size(width: width, height: height))
        else { throw HeadlessError.invalidViewport }
        host.viewport = Size(width: width, height: height)
      case .quit:
        close()
        return HeadlessResponse(id: id, status: .closed)
      }
      // Explicit snapshots are deterministic request boundaries, not a promise that all
      // background app work has finished. Never replay transient events while painting.
      let frame = host.render(
        input: InputState(pointerPosition: pointer, pointerPressPosition: press, pointerDown: pointerDown))
      return HeadlessResponse(
        id: id, status: .frame, viewport: frame.viewport,
        commands: frame.commands,
        focus: HeadlessFocus(
          path: host.interaction.selection, editing: host.interaction.isTextEditing,
          caretOffset: host.interaction.editingLeaf == nil ? nil : host.interaction.caretOffset,
          selectionStart: host.interaction.textSelectionRange?.lowerBound,
          selectionEnd: host.interaction.textSelectionRange?.upperBound))
    } catch let failure as HeadlessError {
      return HeadlessResponse(
        id: id, status: .error,
        error: failure)
    } catch {
      return HeadlessResponse(id: id, status: .error, error: .invalidRequest)
    }
  }

  public func close() {
    guard !isClosed else { return }
    isClosed = true
    host.close()
  }

  /// Emits an initial frame and scheduled updates while serving stdin until EOF or quit.
  /// Reading off the main actor lets the application's asynchronous work continue while idle.
  public func runStandardIO(onlyChanges: Bool = true) async throws {
    let channels = try StandardIOChannels()
    defer { withExtendedLifetime(channels) {} }
    try await runStandardIO(output: channels.output, onlyChanges: onlyChanges)
  }

  func runStandardIO(output: FileHandle, onlyChanges: Bool = true) async throws {
    defer { close() }
    func present(_ frame: HeadlessFrame) throws {
      let response = encode(
        HeadlessResponse(
          status: .frame, viewport: frame.viewport, commands: frame.commands))
      try output.write(contentsOf: Data((response.line + "\n").utf8))
    }
    if let frame = host.lastFrame { try present(frame) }
    host.startPresenting(onlyChanges: onlyChanges) { frame in
      do { try present(frame) } catch { failProcess(error) }
    }
    let reader = BoundedLineReader(handle: .standardInput, limit: Self.maximumLineBytes)
    while !isClosed, let line = try await Task.detached(operation: { try reader.next() }).value {
      let response: HeadlessResponse
      switch line {
      case .bytes(let data):
        if let string = String(data: data, encoding: .utf8) {
          response = self.response(to: string)
        } else {
          response = HeadlessResponse(status: .error, error: .invalidUTF8)
        }
      case .oversized:
        response = HeadlessResponse(status: .error, error: .lineTooLong)
      }
      let encoded = encode(response)
      try output.write(contentsOf: Data((encoded.line + "\n").utf8))
      if let error = encoded.error {
        try FileHandle.standardError.write(contentsOf: Data(("chroma-headless: " + error.rawValue + "\n").utf8))
      }
    }
  }

  public static let maximumLineBytes = 65_536

  private static func validateID(_ id: inout String?) throws {
    guard (id?.utf8.count ?? 0) <= 256 else {
      id = nil
      throw HeadlessError.invalidRequest
    }
  }

  private static func validViewport(_ size: Size) -> Bool {
    size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
      && size.width <= 16_384 && size.height <= 16_384
  }

  private static func validCoordinate(_ value: Float) -> Bool {
    value.isFinite && abs(value) <= 1_000_000
  }

  private func encode(_ response: HeadlessResponse) -> (line: String, error: HeadlessError?) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      return (String(decoding: try encoder.encode(response), as: UTF8.self), response.error)
    } catch {
      // App-produced invalid geometry must not corrupt the JSONL stream.
      let fallback = HeadlessResponse(id: response.id, status: .error, error: .unencodableFrame)
      return (String(decoding: try! encoder.encode(fallback), as: UTF8.self), fallback.error)
    }
  }

  private static func key(_ value: HeadlessKey) -> Key {
    switch value {
    case .up: return .upArrow
    case .down: return .downArrow
    case .left: return .leftArrow
    case .right: return .rightArrow
    case .tab: return .tab
    case .enter: return .enter
    case .escape: return .escape
    case .space: return .space
    case .home: return .home
    case .end: return .end
    case .pageUp: return .pageUp
    case .pageDown: return .pageDown
    case .delete: return .delete
    case .backspace: return .backspace
    case .character(let character): return .character(character)
    }
  }

  private static func modifiers(_ values: [HeadlessModifier]) -> KeyModifiers {
    var result: KeyModifiers = []
    for value in values {
      switch value {
      case .shift: result.insert(.shift)
      case .control: result.insert(.control)
      case .option: result.insert(.option)
      case .command: result.insert(.command)
      case .super: result.insert(.superKey)
      }
    }
    return result
  }

}
