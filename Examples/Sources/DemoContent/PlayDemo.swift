import Chroma
import Foundation

struct PlayDemo: Block {
  let state: PlayState

  @MainActor var body: some Block {
    VStack(spacing: 20) {
      HStack {
        VStack(spacing: 6) {
          Text("Falling blocks").fontScale(1.2).navigationIgnored()
          Text("A little room to clear your head.").fontScale(0.6)
            .foregroundColor(DemoStyle.muted).navigationIgnored()
        }
        Spacer()
        Text("10 x 20 / SEVEN PIECES").fontScale(0.5)
          .foregroundColor(DemoStyle.muted).navigationIgnored()
      }
      HStack(spacing: 24) {
        board
        sidebar
      }.sizing(x: .grow, y: .grow)
    }.padding(24).roundedBackground(DemoStyle.panel, radius: 14)
  }

  @MainActor private var board: some Block {
    Group("Board") {
      GameBoard(state: state)
        .focusTarget(state.focus)
        .keyBindings {
          bind("d", in: .movement, to: .application("game.left"))
          bind("f", in: .movement, to: .application("game.rotate"))
          bind("j", in: .movement, to: .application("game.down"))
          bind("k", in: .movement, to: .application("game.right"))
          bind(.space, in: .movement, to: .application("game.drop"))
          bind("p", in: .movement, to: .application("game.pause"))
        }
        .onCommand(.application("game.left")) {
          state.perform(.left)
          return .handled
        }
        .onCommand(.application("game.right")) {
          state.perform(.right)
          return .handled
        }
        .onCommand(.application("game.rotate")) {
          state.perform(.rotate)
          return .handled
        }
        .onCommand(.application("game.down")) {
          state.perform(.softDrop)
          return .handled
        }
        .onCommand(.application("game.drop")) {
          state.perform(.hardDrop)
          return .handled
        }
        .onCommand(.application("game.pause")) {
          state.togglePause()
          return .handled
        }
        .onCommand(.action(.cancel)) {
          state.pause()
          return .handled
        }
        .onCommand(.navigation(.stepOut)) {
          state.pause()
          return .ignored
        }
    }
  }

  @MainActor private var sidebar: some Block {
    ScrollView("Game controls") {
      VStack(spacing: 14) {
        VStack(spacing: 8) {
          label("SCORE")
          Text(String(format: "%06d", state.game.score)).fontScale(1.5).navigationIgnored()
          Text("SESSION BEST  \(state.bestScore)").fontScale(0.5)
            .foregroundColor(DemoStyle.muted).navigationIgnored()
        }
        HStack(spacing: 32) {
          VStack(spacing: 6) {
            label("LEVEL")
            Text("\(state.game.level)").fontScale(1.0).navigationIgnored()
          }
          VStack(spacing: 6) {
            label("LINES")
            Text("\(state.game.lines)").fontScale(1.0).navigationIgnored()
          }
        }
        VStack(spacing: 12) {
          label("UP NEXT")
          PiecePreview(pieces: Array(state.game.upcoming.prefix(3)))
        }.padding(16).sizing(x: .grow).roundedBackground(DemoStyle.background, radius: 10)
        Button(primaryLabel, fontScale: 0.65, style: DemoStyle.selectedButton) { state.togglePause() }
          .sizing(x: .grow)
        Button("New game", fontScale: 0.6) { state.start() }.sizing(x: .grow)
        VStack(spacing: 9) {
          label("CONTROLS")
          hint("d / k", "Move")
          hint("f", "Rotate")
          hint("j", "Soft drop")
          hint("Space", "Hard drop")
          hint("P / Esc", "Pause")
        }
        Text("l / Enter to play. s to leave.\nSwitching to Chat pauses the game.")
          .fontScale(0.48).foregroundColor(DemoStyle.muted).navigationIgnored()
      }.sizing(x: .grow)
    }.sizing(x: .fixed(250), y: .grow)
  }

  @MainActor private var primaryLabel: String {
    switch state.phase {
    case .ready: "Start game"
    case .playing: "Pause"
    case .paused: "Resume"
    case .gameOver: "Play again"
    }
  }

  private func label(_ text: String) -> some Block {
    Text(text).fontScale(0.5).foregroundColor(DemoStyle.accent).navigationIgnored()
  }

  private func hint(_ key: String, _ action: String) -> some Block {
    HStack {
      Text(key).fontScale(0.52).foregroundColor(DemoStyle.muted).navigationIgnored()
      Spacer()
      Text(action).fontScale(0.52).navigationIgnored()
    }
  }
}

private struct GameBoard: LifecycleElement {
  let state: PlayState
  var focusRule: FocusRule { .control }
  var expandsHorizontally: Bool { true }
  var expandsVertically: Bool { true }

  func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }

  @MainActor func prepareInteraction(in rect: Rect, context: BlockContext) {
    let cell = min((rect.size.width - 12) / 10, (rect.size.height - 12) / 20).rounded(.down)
    guard cell >= 3 else { return }
    let grid = Rect(
      x: rect.minX + (rect.size.width - cell * 10) / 2, y: rect.minY + (rect.size.height - cell * 20) / 2,
      width: cell * 10, height: cell * 20)
    _ = context.buttonState(in: grid) {
      if state.phase != .playing { state.togglePause() }
      state.focus.focus()
    }
  }

  @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
    let cell = min((rect.size.width - 12) / 10, (rect.size.height - 12) / 20).rounded(.down)
    guard cell >= 3 else { return }
    let grid = Rect(
      x: rect.minX + (rect.size.width - cell * 10) / 2,
      y: rect.minY + (rect.size.height - cell * 20) / 2, width: cell * 10, height: cell * 20)
    list.fillRoundedRect(grid, radius: 5, color: DemoStyle.background)
    list.pushClip(grid)
    for row in 0..<FallingBlocksGame.height {
      for column in 0..<FallingBlocksGame.width {
        let tile = Rect(
          x: grid.minX + Float(column) * cell + 1, y: grid.minY + Float(row) * cell + 1,
          width: cell - 2, height: cell - 2)
        if let kind = state.game.board[row * FallingBlocksGame.width + column] {
          list.fillRoundedRect(tile, radius: 3, color: kind.color)
        } else {
          list.strokeRect(tile, width: 0.5, color: DemoStyle.panel)
        }
      }
    }
    if state.phase != .ready && state.phase != .gameOver {
      for position in state.game.ghost.cells {
        list.strokeRoundedRect(
          tile(position, in: grid, cell: cell), radius: 3, width: 1,
          color: DemoStyle.muted)
      }
      for position in state.game.active.cells {
        list.fillRoundedRect(tile(position, in: grid, cell: cell), radius: 3, color: state.game.active.kind.color)
      }
    }
    if state.phase != .playing {
      list.fillRect(grid, color: Color(r: 0.045, g: 0.05, b: 0.065, a: 0.85))
      let title: String =
        switch state.phase {
        case .ready: "Make some space."
        case .paused: "Take a breath."
        case .gameOver: "One more round?"
        case .playing: ""
        }
      let subtitle = state.phase == .paused ? "Enter / click to resume" : "Enter / click to play"
      for (text, scale, offset, color): (String, Float, Float, Color) in [
        (title, 0.9, -24, .white), (subtitle, 0.55, 18, DemoStyle.accent),
      ] {
        let size = context.fontMetrics.measure(text, scale: scale)
        list.text(
          text,
          at: Point(
            x: grid.minX + (grid.size.width - size.width) / 2,
            y: grid.minY + grid.size.height / 2 + offset), color: color, scale: scale)
      }
    }
    list.popClip()
    list.strokeRoundedRect(
      grid, radius: 5, width: 1,
      color: state.focus.isFocused ? DemoStyle.accent : DemoStyle.border)
  }

  private func tile(_ position: GridCell, in rect: Rect, cell: Float) -> Rect {
    Rect(
      x: rect.minX + Float(position.x) * cell + 1, y: rect.minY + Float(position.y) * cell + 1,
      width: cell - 2, height: cell - 2)
  }
}

private struct PiecePreview: LifecycleElement {
  let pieces: [Tetromino]
  var focusRule: FocusRule { .decorative }

  func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    Size(width: proposal.width, height: 138)
  }

  func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
    for (index, piece) in pieces.enumerated() {
      let cells = piece.cells
      let minY = cells.map(\.y).min() ?? 0
      for cell in cells {
        list.fillRoundedRect(
          Rect(
            x: rect.minX + Float(cell.x) * 18, y: rect.minY + Float(index * 48 + (cell.y - minY) * 18),
            width: 16, height: 16), radius: 3, color: piece.color)
      }
      list.text(
        "0\(index + 1)", at: Point(x: rect.maxX - 20, y: rect.minY + Float(index * 48 + 4)),
        color: DemoStyle.muted, scale: 0.5)
    }
  }
}

extension Tetromino {
  var color: Color {
    switch self {
    case .i: Color(r: 0.38, g: 0.78, b: 0.87, a: 1)
    case .o: Color(r: 0.93, g: 0.79, b: 0.4, a: 1)
    case .t: Color(r: 0.7, g: 0.56, b: 0.87, a: 1)
    case .s: Color(r: 0.55, g: 0.8, b: 0.56, a: 1)
    case .z: Color(r: 0.89, g: 0.49, b: 0.53, a: 1)
    case .j: Color(r: 0.47, g: 0.6, b: 0.91, a: 1)
    case .l: Color(r: 0.94, g: 0.64, b: 0.4, a: 1)
    }
  }
}
