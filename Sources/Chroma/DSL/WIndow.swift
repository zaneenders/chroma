@MainActor
public protocol Window {
  var listener: InputListener { get }
  associatedtype EntryBlock: Block
  @BlockParser var entry: EntryBlock { get }
}

/// The Default ``Window`` implementation for setting up state for Chroma.
/// Other ``Window`` types may be added in the future.
public struct TerminalWindow<B: Block>: Window {

  public let listener: InputListener

  private let block: B

  public init(@BlockParser block: () -> B) {
    self.block = block()
    // Default input handler
    self.listener = { input, container in
      switch input {
      case .lowercaseL:
        container.in()
      case .lowercaseS:
        container.out()
      case .lowercaseJ:
        container.down()
      case .lowercaseF:
        container.up()
      case .lowercaseK:
        container.right()
      case .lowercaseD:
        container.left()
      default:
        return input
      }
      return nil  // consume movement commands
    }
  }

  init(_ block: B, listener: @escaping InputListener) {
    self.block = block
    self.listener = listener
  }

  public var entry: B {
    block
  }
}

extension TerminalWindow {
  /// Adds a Object to the environment. Which you can access using the T.self
  /// where T is the type that you are inserting.
  /// You can store value types but you will be unable to mutate them. This
  /// values are accessed on the `@MainActor`.
  public func environment<T>(_ v: T) -> Self {
    // I don't love this but what ever it works for now.
    @Environment(type(of: v).self) var temp
    temp = v
    _ChromaLog.trace("\(v)")
    return self
  }
}

public typealias InputListener = (AsciiKeyCode, inout ChromaController) -> AsciiKeyCode?
extension TerminalWindow {
  public func register(_ listener: @escaping InputListener) -> Self {
    TerminalWindow(self.block, listener: listener)
  }
}

@resultBuilder
public enum WindowBuilder {
  public static func buildBlock(_ window: some Window) -> some Window {
    window
  }
}
