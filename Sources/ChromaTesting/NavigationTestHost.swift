import Chroma

public struct TestKey: ExpressibleByStringLiteral, Sendable {
  public let key: Key

  public init(stringLiteral value: String) {
    precondition(value.count == 1, "A test key must be one character")
    key = .character(value.first!)
  }

  public init(_ key: Key) { self.key = key }

  public static let enter = Self(.enter)
  public static let escape = Self(.escape)
}

@MainActor
public final class NavigationTestHost {
  public let host: HeadlessHost

  public init<A: App>(app: A) throws {
    host = HeadlessHost(size: app.windowSize)
    try host.launch(app)
  }

  public init(
    content: any Block, size: Size = Size(width: 800, height: 600),
    keyBindings: KeyBindings = .modalNavigation
  ) {
    host = HeadlessHost(size: size)
    host.keyBindings = keyBindings
    host.content = content
    host.render()
  }

  public func press(_ inputs: KeyboardInput...) {
    for input in inputs {
      guard let resolved = host.resolve(input) else { continue }
      switch resolved {
      case .command(let command): host.render(input: InputState(commands: [command]))
      case .text(let event): host.render(input: InputState(textEvents: [event]))
      }
      host.render()
    }
  }

  public func press(_ keys: TestKey...) {
    for input in keys {
      let key = input.key
      let text: String? =
        switch key {
        case .character(let character): String(character)
        case .space: " "
        default: nil
        }
      press(KeyboardInput(chord: KeyChord(key), text: text))
    }
  }
}
