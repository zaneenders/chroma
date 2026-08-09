import Chroma

struct DecodedTerminalInput {
  var keys: [TerminalKey] = []
  var shouldClose = false
}

enum TerminalKey: Equatable {
  case character(Character)
  case up, down, left, right
  case tab, enter, escape, backspace, delete
  case home, end, pageUp, pageDown

  var chord: KeyChord? {
    switch self {
    case .character(let character): KeyChord(character)
    case .up: KeyChord(.upArrow)
    case .down: KeyChord(.downArrow)
    case .left: KeyChord(.leftArrow)
    case .right: KeyChord(.rightArrow)
    case .tab: KeyChord(.tab)
    case .enter: KeyChord(.enter)
    case .escape: KeyChord(.escape)
    case .backspace: KeyChord(.backspace)
    case .delete: KeyChord(.delete)
    case .home: KeyChord(.home)
    case .end: KeyChord(.end)
    case .pageUp: KeyChord(.pageUp)
    case .pageDown: KeyChord(.pageDown)
    }
  }
}

struct TerminalInputDecoder {
  private var pending: [UInt8] = []

  mutating func decode(_ bytes: [UInt8]) -> DecodedTerminalInput {
    pending.append(contentsOf: bytes)
    var result = DecodedTerminalInput()
    var index = 0
    while index < pending.count {
      let byte = pending[index]
      if byte == 3 || byte == 4 { result.shouldClose = true; index += 1; continue }
      if byte == 0x1B {
        guard index + 1 < pending.count else { break }
        guard pending[index + 1] == 0x5B else {
          result.keys.append(.escape); index += 1; continue
        }
        guard let end = pending[(index + 2)...].firstIndex(where: { $0 >= 0x40 && $0 <= 0x7E }) else { break }
        let sequence = Array(pending[index...end])
        if let key = escapeKey(sequence) { result.keys.append(key) }
        index = end + 1
        continue
      }
      switch byte {
      case 9: result.keys.append(.tab); index += 1
      case 10, 13: result.keys.append(.enter); index += 1
      case 8, 127: result.keys.append(.backspace); index += 1
      case 32...126:
        result.keys.append(.character(Character(UnicodeScalar(byte))))
        index += 1
      default:
        let length = utf8Length(byte)
        guard length > 1, index + length <= pending.count else { break }
        let slice = pending[index..<(index + length)]
        if let string = String(bytes: slice, encoding: .utf8), let character = string.first {
          result.keys.append(.character(character))
        }
        index += length
      }
    }
    pending.removeFirst(index)
    return result
  }

  private func escapeKey(_ bytes: [UInt8]) -> TerminalKey? {
    guard let final = bytes.last else { return nil }
    if bytes.count == 3 {
      switch final {
      case 0x41: return .up
      case 0x42: return .down
      case 0x43: return .right
      case 0x44: return .left
      case 0x48: return .home
      case 0x46: return .end
      default: return nil
      }
    }
    guard final == 0x7E else { return nil }
    switch String(bytes: bytes.dropFirst(2).dropLast(), encoding: .utf8) {
    case "3": return .delete
    case "5": return .pageUp
    case "6": return .pageDown
    case "1", "7": return .home
    case "4", "8": return .end
    default: return nil
    }
  }

  private func utf8Length(_ first: UInt8) -> Int {
    if first & 0xE0 == 0xC0 { return 2 }
    if first & 0xF0 == 0xE0 { return 3 }
    if first & 0xF8 == 0xF0 { return 4 }
    return 1
  }
}
