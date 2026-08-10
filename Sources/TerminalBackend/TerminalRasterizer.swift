import Chroma
import Foundation

public struct TerminalRGB: Equatable, Sendable {
  public var r: UInt8
  public var g: UInt8
  public var b: UInt8

  public init(r: UInt8, g: UInt8, b: UInt8) {
    self.r = r
    self.g = g
    self.b = b
  }

  public static let black = TerminalRGB(r: 0, g: 0, b: 0)
  public static let white = TerminalRGB(r: 255, g: 255, b: 255)
}

public struct TerminalCell: Equatable, Sendable {
  public var glyph: Character
  public var foreground: TerminalRGB
  public var background: TerminalRGB

  public init(
    glyph: Character = " ",
    foreground: TerminalRGB = .white,
    background: TerminalRGB = .black
  ) {
    self.glyph = glyph
    self.foreground = foreground
    self.background = background
  }
}

public struct TerminalFrame: Equatable, Sendable {
  public let columns: Int
  public let rows: Int
  public var cells: [TerminalCell]

  public init(columns: Int, rows: Int, filling cell: TerminalCell = TerminalCell()) {
    precondition(columns > 0 && rows > 0)
    self.columns = columns
    self.rows = rows
    self.cells = Array(repeating: cell, count: columns * rows)
  }

  public subscript(column column: Int, row row: Int) -> TerminalCell {
    get { cells[row * columns + column] }
    set { cells[row * columns + column] = newValue }
  }

  public func text(row: Int) -> String {
    guard row >= 0, row < rows else { return "" }
    return String(cells[(row * columns)..<((row + 1) * columns)].map(\.glyph))
  }
}

public struct TerminalRasterizer: Sendable {
  public init() {}

  public func rasterize(
    _ commands: [DrawCommand],
    columns: Int,
    rows: Int,
    background: Color = .black,
    pointsPerCell: Size = Size(width: 1, height: 1)
  ) -> TerminalFrame {
    let backgroundRGB = rgb(background, over: .black)
    var frame = TerminalFrame(
      columns: columns,
      rows: rows,
      filling: TerminalCell(foreground: .white, background: backgroundRGB))
    var clips = [CellRect(x0: 0, y0: 0, x1: columns, y1: rows)]

    for command in commands {
      switch command {
      case .pushClip(let rect):
        clips.append(clips.last!.intersection(quantized(rect, pointsPerCell: pointsPerCell)) ?? .empty)
      case .popClip:
        if clips.count > 1 { clips.removeLast() }
      case .fillRect(let rect, let color), .fillRoundedRect(let rect, _, let color):
        fill(
          rect, color: color, clip: clips.last!, pointsPerCell: pointsPerCell,
          frame: &frame)
      case .strokeRect(let rect, _, let color):
        stroke(
          rect, color: color, clip: clips.last!, pointsPerCell: pointsPerCell,
          frame: &frame)
      case .strokeRoundedRect(let rect, _, _, let color):
        stroke(
          rect, color: color, clip: clips.last!, pointsPerCell: pointsPerCell,
          suppressCompactBorder: true, frame: &frame)
      case .text(let position, let text, let color, _):
        drawText(
          text, at: position, color: color, clip: clips.last!,
          pointsPerCell: pointsPerCell, frame: &frame)
      }
    }
    return frame
  }

  private func fill(
    _ rect: Rect, color: Color, clip: CellRect, pointsPerCell: Size,
    frame: inout TerminalFrame
  ) {
    guard let area = quantizedFill(rect, pointsPerCell: pointsPerCell).intersection(clip) else {
      return
    }
    for y in area.y0..<area.y1 {
      for x in area.x0..<area.x1 {
        var cell = frame[column: x, row: y]
        cell.background = rgb(color, over: cell.background)
        cell.glyph = " "
        frame[column: x, row: y] = cell
      }
    }
  }

  private func stroke(
    _ rect: Rect, color: Color, clip: CellRect, pointsPerCell: Size,
    suppressCompactBorder: Bool = false, frame: inout TerminalFrame
  ) {
    let area = quantized(rect, pointsPerCell: pointsPerCell)
    guard area.x1 > area.x0, area.y1 > area.y0 else { return }

    // Rounded controls depend on their fill more than their outline in a terminal.
    // When top and bottom are adjacent, box glyphs consume every interior row and
    // visually overpower the label. Keep larger rounded containers outlined while
    // rendering compact controls as clean color-backed cells.
    if suppressCompactBorder, area.y1 - area.y0 <= 3 { return }
    let foreground = rgb(color, over: .black)
    func put(_ x: Int, _ y: Int, _ glyph: Character) {
      guard clip.contains(x, y), x >= 0, x < frame.columns, y >= 0, y < frame.rows else { return }
      var cell = frame[column: x, row: y]

      // Borders are commonly emitted after their content. A one-point GUI border
      // can quantize onto the same terminal row as a label, so replacing occupied
      // cells here would erase headers, footers, and short button labels. Preserve
      // semantic content and draw the border through otherwise empty cells.
      guard cell.glyph == " " else { return }
      cell.glyph = glyph
      cell.foreground = foreground
      frame[column: x, row: y] = cell
    }
    let left = area.x0
    let right = area.x1 - 1
    let top = area.y0
    let bottom = area.y1 - 1
    if left == right || top == bottom {
      for x in left...right { put(x, top, top == bottom ? "─" : (x == left ? "┌" : x == right ? "┐" : "─")) }
      if top != bottom {
        for y in (top + 1)..<bottom {
          put(left, y, "│")
          if right != left { put(right, y, "│") }
        }
      }
      if bottom != top { for x in left...right { put(x, bottom, x == left ? "└" : x == right ? "┘" : "─") } }
      return
    }
    put(left, top, "┌")
    put(right, top, "┐")
    put(left, bottom, "└")
    put(right, bottom, "┘")
    if right > left + 1 {
      for x in (left + 1)..<right {
        put(x, top, "─")
        put(x, bottom, "─")
      }
    }
    if bottom > top + 1 {
      for y in (top + 1)..<bottom {
        put(left, y, "│")
        put(right, y, "│")
      }
    }
  }

  private func drawText(
    _ text: String, at position: Point, color: Color, clip: CellRect,
    pointsPerCell: Size, frame: inout TerminalFrame
  ) {
    var x = Int((position.x / pointsPerCell.width).rounded())
    var y = Int((position.y / pointsPerCell.height).rounded())
    let foreground = rgb(color, over: .black)
    let startX = x
    for character in text {
      if character == "\n" {
        y += 1
        x = startX
        continue
      }
      if clip.contains(x, y), x >= 0, x < frame.columns, y >= 0, y < frame.rows {
        var cell = frame[column: x, row: y]
        cell.glyph = character
        cell.foreground = foreground
        frame[column: x, row: y] = cell
      }
      x += 1
    }
  }

  private func quantized(_ rect: Rect, pointsPerCell: Size) -> CellRect {
    CellRect(
      x0: Int(floor(rect.minX / pointsPerCell.width)),
      y0: Int(floor(rect.minY / pointsPerCell.height)),
      x1: Int(ceil(rect.maxX / pointsPerCell.width)),
      y1: Int(ceil(rect.maxY / pointsPerCell.height)))
  }

  /// Assign a fill to cells by their center point instead of including every cell
  /// touched by a sub-cell edge. This keeps adjacent GUI controls from bleeding
  /// into each other's terminal rows and columns while still guaranteeing that a
  /// very thin caret or scroll indicator occupies at least one cell.
  private func quantizedFill(_ rect: Rect, pointsPerCell: Size) -> CellRect {
    func range(_ minimum: Float, _ maximum: Float, cellSize: Float) -> (Int, Int) {
      var lower = Int(ceil(minimum / cellSize - 0.5))
      var upper = Int(ceil(maximum / cellSize - 0.5))
      if upper <= lower, maximum > minimum {
        lower = Int(floor(minimum / cellSize))
        upper = lower + 1
      }
      return (lower, upper)
    }

    let x = range(rect.minX, rect.maxX, cellSize: pointsPerCell.width)
    let y = range(rect.minY, rect.maxY, cellSize: pointsPerCell.height)
    return CellRect(x0: x.0, y0: y.0, x1: x.1, y1: y.1)
  }

  private func rgb(_ color: Color, over background: TerminalRGB) -> TerminalRGB {
    let alpha = max(0, min(1, color.a))
    func channel(_ source: Float, _ destination: UInt8) -> UInt8 {
      let value = max(0, min(1, source)) * alpha + Float(destination) / 255 * (1 - alpha)
      return UInt8(max(0, min(255, Int((value * 255).rounded()))))
    }
    return TerminalRGB(
      r: channel(color.r, background.r),
      g: channel(color.g, background.g),
      b: channel(color.b, background.b))
  }
}

private struct CellRect {
  var x0: Int
  var y0: Int
  var x1: Int
  var y1: Int

  static let empty = CellRect(x0: 0, y0: 0, x1: 0, y1: 0)

  func intersection(_ other: CellRect) -> CellRect? {
    let result = CellRect(
      x0: max(x0, other.x0), y0: max(y0, other.y0),
      x1: min(x1, other.x1), y1: min(y1, other.y1))
    return result.x1 > result.x0 && result.y1 > result.y0 ? result : nil
  }

  func contains(_ x: Int, _ y: Int) -> Bool {
    x >= x0 && x < x1 && y >= y0 && y < y1
  }
}
