import Chroma
import Foundation

/// A request in the headless JSONL protocol.
public struct HeadlessRequest: Codable, Sendable {
  public let version: Int
  public let id: HeadlessRequestID?
  public let op: HeadlessOperation
  public let key: HeadlessKey?
  public let modifiers: [HeadlessModifier]?
  public let text: String?
  public let x: Float?
  public let y: Float?
  public let phase: HeadlessPointerPhase?
  public let width: Float?
  public let height: Float?

  public init(
    version: Int = 1, id: HeadlessRequestID? = nil, op: HeadlessOperation,
    key: HeadlessKey? = nil, modifiers: [HeadlessModifier]? = nil, text: String? = nil,
    x: Float? = nil, y: Float? = nil, phase: HeadlessPointerPhase? = nil,
    width: Float? = nil, height: Float? = nil
  ) {
    self.version = version
    self.id = id
    self.op = op
    self.key = key
    self.modifiers = modifiers
    self.text = text
    self.x = x
    self.y = y
    self.phase = phase
    self.width = width
    self.height = height
  }
}

/// Focus and editing state reported by a headless frame.
public struct HeadlessFocus: Codable, Sendable {
  public let path: [Int]?
  public let editing: Bool
  public let caretOffset: Int?
  public let selectionStart: Int?
  public let selectionEnd: Int?

  public init(
    path: [Int]? = nil, editing: Bool, caretOffset: Int? = nil,
    selectionStart: Int? = nil, selectionEnd: Int? = nil
  ) {
    self.path = path
    self.editing = editing
    self.caretOffset = caretOffset
    self.selectionStart = selectionStart
    self.selectionEnd = selectionEnd
  }
}

/// A frame, closed acknowledgement, or error in the headless JSONL protocol.
public struct HeadlessResponse: Codable, Sendable {
  public let version: Int
  public let id: HeadlessRequestID?
  public let status: HeadlessStatus
  public let viewport: Size?
  public let commands: [DrawCommand]?
  public let focus: HeadlessFocus?
  public let error: HeadlessError?

  public init(
    version: Int = 1, id: HeadlessRequestID? = nil, status: HeadlessStatus,
    viewport: Size? = nil, commands: [DrawCommand]? = nil,
    focus: HeadlessFocus? = nil, error: HeadlessError? = nil
  ) {
    self.version = version
    self.id = id
    self.status = status
    self.viewport = viewport
    self.commands = commands
    self.focus = focus
    self.error = error
  }
}

/// Correlation data, encoded as a JSON string rather than an object.
public struct HeadlessRequestID: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.init(rawValue: value) }
  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public enum HeadlessOperation: String, Codable, Sendable {
  case frame, key, pointer, scroll, resize, quit
}

public enum HeadlessPointerPhase: String, Codable, Sendable {
  case move, down, up
}

public enum HeadlessModifier: String, Codable, Sendable {
  case shift, control, option, command, `super`
}

public enum HeadlessStatus: String, Codable, Sendable {
  case frame, closed, error
}

public enum HeadlessError: String, Codable, Sendable, Error {
  case invalidViewport = "invalid_viewport"
  case lineTooLong = "line_too_long"
  case invalidRequest = "invalid_request"
  case unsupportedVersion = "unsupported_version"
  case unknownOperation = "unknown_operation"
  case invalidPointerTransition = "invalid_pointer_transition"
  case invalidUTF8 = "invalid_utf8"
  case unencodableFrame = "unencodable_frame"
  case closed
}

/// Named keys and single-character keys retain their string representation on the wire.
public enum HeadlessKey: Codable, Sendable, Equatable {
  case up, down, left, right, tab, enter, escape, space, home, end, pageUp, pageDown, delete, backspace
  case character(Character)

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    switch value {
    case "up": self = .up
    case "down": self = .down
    case "left": self = .left
    case "right": self = .right
    case "tab": self = .tab
    case "enter": self = .enter
    case "escape": self = .escape
    case "space": self = .space
    case "home": self = .home
    case "end": self = .end
    case "pageUp": self = .pageUp
    case "pageDown": self = .pageDown
    case "delete": self = .delete
    case "backspace": self = .backspace
    default:
      guard value.count == 1, let character = value.first else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid headless key")
      }
      self = .character(character)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .character(let character): try container.encode(String(character))
    case .up: try container.encode("up")
    case .down: try container.encode("down")
    case .left: try container.encode("left")
    case .right: try container.encode("right")
    case .tab: try container.encode("tab")
    case .enter: try container.encode("enter")
    case .escape: try container.encode("escape")
    case .space: try container.encode("space")
    case .home: try container.encode("home")
    case .end: try container.encode("end")
    case .pageUp: try container.encode("pageUp")
    case .pageDown: try container.encode("pageDown")
    case .delete: try container.encode("delete")
    case .backspace: try container.encode("backspace")
    }
  }
}
