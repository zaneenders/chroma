import Chroma

@MainActor
public final class TerminalRenderer: Renderer {
  public let name = "Terminal"
  public var content: (any Block)?
  public var onClose: (() -> Void)?
  public private(set) var lastFrame: TerminalFrame?

  package let interaction = Interaction()

  private var keyBindings = KeyBindings()
  private var minimumRefreshRate: Double = 0
  private var decoder = TerminalInputDecoder()
  private var running = false
  private let rasterizer = TerminalRasterizer()

  /// Chroma's layout remains in its native point coordinate system. The terminal
  /// rasterizer projects those points onto character cells at the final step.
  /// Keeping native metrics means font scales, padding, and fixed dimensions do
  /// not collapse to fractions of a terminal cell.
  public let pointsPerCell: Size

  public init(pointsPerCell: Size = Size(width: 11, height: 28)) {
    precondition(pointsPerCell.width > 0 && pointsPerCell.height > 0)
    self.pointsPerCell = pointsPerCell
  }

  public func setKeyBindings(_ bindings: KeyBindings) {
    keyBindings = bindings
  }

  public func setMinimumRefreshRate(_ refreshRate: Double) {
    minimumRefreshRate = max(0, refreshRate)
  }

  public func run(title: String) {
    let session: TerminalSession
    do {
      session = try TerminalSession()
    } catch {
      return
    }
    running = true
    defer {
      running = false
      session.restore()
      onClose?()
    }

    var presenter = TerminalPresenter()
    var size = session.windowSize()
    session.write("\u{1B}]0;\(title)\u{7}")

    // Chroma discovers the focus tree while drawing its first frame, then selects
    // the first leaf in endFrame(). Prime that retained tree before presenting so
    // the initial visible frame already reflects the selection.
    _ = render(columns: size.columns, rows: size.rows)
    session.write(presenter.encode(render(columns: size.columns, rows: size.rows)))

    while running {
      let timeout: Int32 =
        minimumRefreshRate > 0
        ? Int32(max(1, min(Double(Int32.max), 1000 / minimumRefreshRate))) : 100
      var input = InputState()
      if let bytes = session.read(timeoutMilliseconds: timeout) {
        if bytes.isEmpty { break }
        let decoded = decoder.decode(bytes)
        if decoded.shouldClose { break }
        input = translate(decoded.keys)
      }
      let newSize = session.windowSize()
      let resized = newSize.columns != size.columns || newSize.rows != size.rows
      size = newSize
      if input != InputState() || resized || minimumRefreshRate > 0 {
        session.write(presenter.encode(render(columns: size.columns, rows: size.rows, input: input)))

        // An action can mutate model state after an earlier sibling has already been
        // evaluated in this frame. Chroma requests another frame in that case; present
        // it immediately rather than waiting for the baseline refresh interval.
        if interaction.consumeRedrawRequest() {
          session.write(presenter.encode(render(columns: size.columns, rows: size.rows)))
        }
      }
    }
  }

  public func close() {
    running = false
  }

  @discardableResult
  public func render(
    columns: Int,
    rows: Int,
    input: InputState = InputState()
  ) -> TerminalFrame {
    let previousInteraction = Interaction.current
    Interaction.current = interaction
    defer { Interaction.current = previousInteraction }

    interaction.beginFrame(input: input)
    var drawList = DrawList()
    if let content {
      BlockEngine.draw(
        content,
        into: &drawList,
        in: Rect(
          x: 0,
          y: 0,
          width: Float(columns) * pointsPerCell.width,
          height: Float(rows) * pointsPerCell.height),
        context: context)
    }
    interaction.endFrame()
    let frame = rasterizer.rasterize(
      drawList.commands,
      columns: columns,
      rows: rows,
      pointsPerCell: pointsPerCell)
    lastFrame = frame
    return frame
  }

  private func translate(_ keys: [TerminalKey]) -> InputState {
    var commands: [Command] = []
    var edits: [TextEditEvent] = []
    for key in keys {
      let chord = key.chord
      if let chord, let resolution = keyBindings.command(for: chord) {
        guard let command = resolution else { continue }
        if interaction.mode == .editing, case .editing(let editing) = command {
          edits.append(editEvent(editing))
        } else {
          commands.append(command)
        }
        continue
      }
      if interaction.mode == .editing {
        switch key {
        case .character(let character): edits.append(.insert(String(character)))
        case .backspace: edits.append(.backspace)
        case .delete: edits.append(.deleteForward)
        case .left: edits.append(.moveCaretLeft)
        case .right: edits.append(.moveCaretRight)
        case .home: edits.append(.moveCaretToStart)
        case .end: edits.append(.moveCaretToEnd)
        case .enter: edits.append(.submit)
        case .escape: edits.append(.endEditing)
        default: break
        }
      } else {
        switch key {
        case .up: commands.append(.navigation(.up))
        case .down: commands.append(.navigation(.down))
        case .left: commands.append(.navigation(.left))
        case .right: commands.append(.navigation(.right))
        case .tab: commands.append(.navigation(.next))
        case .enter, .character(" "): commands.append(.action(.activate))
        case .pageUp: commands.append(.navigation(.pageUp))
        case .pageDown: commands.append(.navigation(.pageDown))
        case .home: commands.append(.navigation(.home))
        case .end: commands.append(.navigation(.end))
        default: break
        }
      }
    }
    return InputState(semanticCommands: commands, textEvents: edits)
  }

  private func editEvent(_ command: EditingCommand) -> TextEditEvent {
    switch command {
    case .backspace: .backspace
    case .deleteForward: .deleteForward
    case .moveCaretLeft: .moveCaretLeft
    case .moveCaretRight: .moveCaretRight
    case .moveCaretToStart: .moveCaretToStart
    case .moveCaretToEnd: .moveCaretToEnd
    case .selectAll: .selectAll
    case .submit: .submit
    case .endEditing: .endEditing
    case .paste, .copy: .insert("")
    }
  }
}

public protocol TerminalApp: App {}

extension TerminalApp {
  @MainActor
  public static func main() {
    let app = Self()
    app.run(on: TerminalRenderer())
  }
}
