/// Synthesizes bitmaps for the symbol ranges terminal programs emit but the
/// hand-drawn ASCII font does not cover: box drawing, block elements, braille,
/// arrows, geometric shapes, and Powerline separators. Without these, the
/// atlas silently substitutes a blank space, which breaks shell prompts
/// (`➜`, `✗`), TUI borders (`╭──╮`), and dashboards.
///
/// Hand-drawn glyphs in `Font20x28.glyphs` always win; these fill the
/// gaps around them.
public enum GlyphGenerator {
  public static let generated: [UInt32: Glyph] = buildGlyphs()
}

/// 20×28 pixel canvas matching `FontMetrics`.
private struct Canvas {
  static let width = 20
  static let height = 28
  var rows = [UInt32](repeating: 0, count: Canvas.height)

  var glyph: Glyph { Glyph(rows: rows) }

  mutating func set(_ x: Int, _ y: Int) {
    guard x >= 0, x < Canvas.width, y >= 0, y < Canvas.height else { return }
    rows[y] |= UInt32(1) << UInt32(Canvas.width - x - 1)
  }

  mutating func fillRect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
    for y in min(y0, y1)...max(y0, y1) {
      for x in min(x0, x1)...max(x0, x1) {
        set(x, y)
      }
    }
  }

  /// Bresenham line with a square brush centered on the line.
  mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, thickness: Int = 2) {
    let dx = abs(x1 - x0)
    let dy = abs(y1 - y0)
    let sx = x0 < x1 ? 1 : -1
    let sy = y0 < y1 ? 1 : -1
    var error = dx - dy
    var x = x0
    var y = y0
    let half = (thickness - 1) / 2
    while true {
      fillRect(x - half, y - half, x - half + thickness - 1, y - half + thickness - 1)
      if x == x1 && y == y1 { break }
      let doubled = 2 * error
      if doubled > -dy {
        error -= dy
        x += sx
      }
      if doubled < dx {
        error += dx
        y += sy
      }
    }
  }

  mutating func disc(centerX cx: Double, centerY cy: Double, radius r: Double) {
    for y in 0..<Canvas.height {
      for x in 0..<Canvas.width {
        let dx = Double(x) + 0.5 - cx
        let dy = Double(y) + 0.5 - cy
        if dx * dx + dy * dy <= r * r { set(x, y) }
      }
    }
  }

  mutating func ring(centerX cx: Double, centerY cy: Double, radius r: Double, thickness: Double) {
    for y in 0..<Canvas.height {
      for x in 0..<Canvas.width {
        let dx = Double(x) + 0.5 - cx
        let dy = Double(y) + 0.5 - cy
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= r && distance >= r - thickness { set(x, y) }
      }
    }
  }

  /// Up-pointing triangle: apex at (`centerX`, `top`), base on `bottom`.
  mutating func triangleUp(centerX cx: Int, top: Int, bottom: Int, halfWidth: Int) {
    let span = max(1, bottom - top)
    for y in top...bottom {
      let half = Int((Double(y - top) / Double(span)) * Double(halfWidth) + 0.5)
      fillRect(cx - half, y, cx + half, y)
    }
  }

  mutating func flipHorizontally() {
    for y in 0..<Canvas.height {
      var flipped: UInt32 = 0
      for x in 0..<Canvas.width where rows[y] & (UInt32(1) << UInt32(Canvas.width - x - 1)) != 0 {
        flipped |= UInt32(1) << UInt32(x)
      }
      rows[y] = flipped
    }
  }
}

// MARK: - Box drawing

/// Stroke style for one arm of a box-drawing glyph.
private enum Stroke {
  case none
  case light
  case heavy
  case double
  case dashedLight
  case dashedHeavy
}

private enum Box {
  /// Horizontal stroke bands (rows); vertical bands (columns).
  static let light = 13...14
  static let heavy = 12...15
  static let doubleOuter = 10...11
  static let doubleInner = 16...17
  static let lightV = 9...10
  static let heavyV = 8...11
  static let doubleOuterV = 6...7
  static let doubleInnerV = 12...13

  enum Direction { case up, down, left, right }

  /// Draws one arm from the cell center to an edge. Double arms extend past
  /// the center so tees and crosses bridge both stroke bands.
  static func arm(_ canvas: inout Canvas, direction: Direction, stroke: Stroke) {
    switch (stroke, direction) {
    case (.none, _):
      break
    case (.light, .up):
      canvas.fillRect(lightV.lowerBound, 0, lightV.upperBound, light.upperBound)
    case (.light, .down):
      canvas.fillRect(lightV.lowerBound, light.lowerBound, lightV.upperBound, Canvas.height - 1)
    case (.light, .left):
      canvas.fillRect(0, light.lowerBound, lightV.upperBound, light.upperBound)
    case (.light, .right):
      canvas.fillRect(lightV.lowerBound, light.lowerBound, Canvas.width - 1, light.upperBound)
    case (.heavy, .up):
      canvas.fillRect(heavyV.lowerBound, 0, heavyV.upperBound, heavy.upperBound)
    case (.heavy, .down):
      canvas.fillRect(heavyV.lowerBound, heavy.lowerBound, heavyV.upperBound, Canvas.height - 1)
    case (.heavy, .left):
      canvas.fillRect(0, heavy.lowerBound, heavyV.upperBound, heavy.upperBound)
    case (.heavy, .right):
      canvas.fillRect(heavyV.lowerBound, heavy.lowerBound, Canvas.width - 1, heavy.upperBound)
    case (.double, .up):
      canvas.fillRect(doubleOuterV.lowerBound, 0, doubleOuterV.upperBound, doubleInner.upperBound)
      canvas.fillRect(doubleInnerV.lowerBound, 0, doubleInnerV.upperBound, doubleInner.upperBound)
    case (.double, .down):
      canvas.fillRect(doubleOuterV.lowerBound, doubleOuter.lowerBound, doubleOuterV.upperBound, Canvas.height - 1)
      canvas.fillRect(doubleInnerV.lowerBound, doubleOuter.lowerBound, doubleInnerV.upperBound, Canvas.height - 1)
    case (.double, .left):
      canvas.fillRect(0, doubleOuter.lowerBound, doubleInnerV.upperBound, doubleOuter.upperBound)
      canvas.fillRect(0, doubleInner.lowerBound, doubleInnerV.upperBound, doubleInner.upperBound)
    case (.double, .right):
      canvas.fillRect(doubleOuterV.lowerBound, doubleOuter.lowerBound, Canvas.width - 1, doubleOuter.upperBound)
      canvas.fillRect(doubleOuterV.lowerBound, doubleInner.lowerBound, Canvas.width - 1, doubleInner.upperBound)
    case (.dashedLight, let direction):
      dashedArm(&canvas, direction: direction, band: light, cross: lightV)
    case (.dashedHeavy, let direction):
      dashedArm(&canvas, direction: direction, band: heavy, cross: heavyV)
    }
  }

  private static func dashedArm(
    _ canvas: inout Canvas, direction: Direction, band: ClosedRange<Int>, cross: ClosedRange<Int>
  ) {
    switch direction {
    case .up, .down:
      let rows = direction == .up ? 0...band.upperBound : band.lowerBound...(Canvas.height - 1)
      for y in rows where y % 6 < 3 {
        canvas.fillRect(cross.lowerBound, y, cross.upperBound, y)
      }
    case .left, .right:
      let cols = direction == .left ? 0...cross.upperBound : cross.lowerBound...(Canvas.width - 1)
      for x in cols where x % 6 < 3 {
        canvas.fillRect(x, band.lowerBound, x, band.upperBound)
      }
    }
  }

  /// Double-stroke corners need true elbows; the generic arm model would
  /// fill the inner wall all the way to the far band.
  static func doubleCorner(down: Bool, right: Bool) -> Canvas {
    var canvas = Canvas()
    let outerV = right ? doubleOuterV : doubleInnerV
    let innerV = right ? doubleInnerV : doubleOuterV
    let outerH = down ? doubleOuter : doubleInner
    let innerH = down ? doubleInner : doubleOuter
    let outerVRange = down ? outerH.lowerBound...(Canvas.height - 1) : 0...outerH.upperBound
    let innerVRange = down ? innerH.lowerBound...(Canvas.height - 1) : 0...innerH.upperBound
    let outerHRange = right ? outerV.lowerBound...(Canvas.width - 1) : 0...outerV.upperBound
    let innerHRange = right ? innerV.lowerBound...(Canvas.width - 1) : 0...innerV.upperBound
    canvas.fillRect(outerV.lowerBound, outerVRange.lowerBound, outerV.upperBound, outerVRange.upperBound)
    canvas.fillRect(innerV.lowerBound, innerVRange.lowerBound, innerV.upperBound, innerVRange.upperBound)
    canvas.fillRect(outerHRange.lowerBound, outerH.lowerBound, outerHRange.upperBound, outerH.upperBound)
    canvas.fillRect(innerHRange.lowerBound, innerH.lowerBound, innerHRange.upperBound, innerH.upperBound)
    return canvas
  }

  /// Rounded light corner as a quarter ellipse between the center lines.
  static func roundedCorner(down: Bool, right: Bool) -> Canvas {
    var canvas = Canvas()
    // Trace a quarter ellipse without platform math-library imports. Sampling
    // one coordinate and deriving the other from x²/a² + y²/b² = 1 is enough
    // at this fixed 20×28 bitmap resolution.
    for step in 0...28 {
      let unitY = Double(step) / 28
      let unitX = (max(0, 1 - unitY * unitY)).squareRoot()
      let x = right ? 19 - Int(unitX * 9.5 + 0.5) : Int(unitX * 9.5 + 0.5)
      // A "down" corner (╭ ╮) opens toward the bottom edge, so its arc lives
      // in the bottom half of the cell, matching the square corners (┌ ┐).
      let y = down ? 27 - Int(unitY * 13.5 + 0.5) : Int(unitY * 13.5 + 0.5)
      canvas.fillRect(x - 1, y - 1, x, y)
    }
    return canvas
  }
}

// MARK: - Glyph table construction

private func buildGlyphs() -> [UInt32: Glyph] {
  var out: [UInt32: Glyph] = [:]

  // MARK: Box drawing (U+2500–257F)
  let n = Stroke.none
  let l = Stroke.light
  let h = Stroke.heavy
  let d = Stroke.double
  let dl = Stroke.dashedLight
  let dh = Stroke.dashedHeavy
  let boxArms: [UInt32: (up: Stroke, down: Stroke, left: Stroke, right: Stroke)] = [
    0x2500: (n, n, l, l), 0x2501: (n, n, h, h), 0x2502: (l, l, n, n), 0x2503: (h, h, n, n),
    0x2504: (n, n, dl, dl), 0x2505: (n, n, dh, dh), 0x2506: (dl, dl, n, n), 0x2507: (dh, dh, n, n),
    0x2508: (n, n, dl, dl), 0x2509: (n, n, dh, dh), 0x250A: (dl, dl, n, n), 0x250B: (dh, dh, n, n),
    0x250C: (n, l, n, l), 0x250D: (n, l, n, h), 0x250E: (n, h, n, l), 0x250F: (n, h, n, h),
    0x2510: (n, l, l, n), 0x2511: (n, l, h, n), 0x2512: (n, h, l, n), 0x2513: (n, h, h, n),
    0x2514: (l, n, n, l), 0x2515: (l, n, n, h), 0x2516: (h, n, n, l), 0x2517: (h, n, n, h),
    0x2518: (l, n, l, n), 0x2519: (l, n, h, n), 0x251A: (h, n, l, n), 0x251B: (h, n, h, n),
    0x251C: (l, l, n, l), 0x251D: (l, l, n, h), 0x251E: (h, l, n, l), 0x251F: (l, h, n, l),
    0x2520: (h, h, n, l), 0x2521: (h, l, n, h), 0x2522: (l, h, n, h), 0x2523: (h, h, n, h),
    0x2524: (l, l, l, n), 0x2525: (l, l, h, n), 0x2526: (h, l, l, n), 0x2527: (l, h, l, n),
    0x2528: (h, h, l, n), 0x2529: (h, l, h, n), 0x252A: (l, h, h, n), 0x252B: (h, h, h, n),
    0x252C: (n, l, l, l), 0x252D: (n, l, h, l), 0x252E: (n, l, l, h), 0x252F: (n, l, h, h),
    0x2530: (n, h, l, l), 0x2531: (n, h, h, l), 0x2532: (n, h, l, h), 0x2533: (n, h, h, h),
    0x2534: (l, n, l, l), 0x2535: (l, n, h, l), 0x2536: (l, n, l, h), 0x2537: (l, n, h, h),
    0x2538: (h, n, l, l), 0x2539: (h, n, h, l), 0x253A: (h, n, l, h), 0x253B: (h, n, h, h),
    0x253C: (l, l, l, l), 0x253D: (l, l, h, l), 0x253E: (l, l, l, h), 0x253F: (l, l, h, h),
    0x2540: (h, l, l, l), 0x2541: (l, h, l, l), 0x2542: (h, h, l, l), 0x2543: (h, l, h, l),
    0x2544: (h, l, l, h), 0x2545: (l, h, h, l), 0x2546: (l, h, l, h), 0x2547: (h, l, h, h),
    0x2548: (l, h, h, h), 0x2549: (h, h, h, l), 0x254A: (h, h, l, h), 0x254B: (h, h, h, h),
    0x254C: (n, n, dl, dl), 0x254D: (n, n, dh, dh), 0x254E: (dl, dl, n, n), 0x254F: (dh, dh, n, n),
    0x2550: (n, n, d, d), 0x2551: (d, d, n, n),
    0x2552: (n, l, n, d), 0x2553: (n, d, n, l), 0x2555: (n, l, d, n), 0x2556: (n, d, l, n),
    0x2558: (l, n, n, d), 0x2559: (d, n, n, l), 0x255B: (l, n, d, n), 0x255C: (d, n, l, n),
    0x255E: (l, l, n, d), 0x255F: (d, d, n, l), 0x2560: (d, d, n, d),
    0x2561: (l, l, d, n), 0x2562: (d, d, l, n), 0x2563: (d, d, d, n),
    0x2564: (n, l, d, d), 0x2565: (n, d, l, l), 0x2566: (n, d, d, d),
    0x2567: (l, n, d, d), 0x2568: (d, n, l, l), 0x2569: (d, n, d, d),
    0x256A: (l, l, d, d), 0x256B: (d, d, l, l), 0x256C: (d, d, d, d),
    0x2574: (n, n, h, n), 0x2575: (h, n, n, n), 0x2576: (n, n, n, h), 0x2577: (n, h, n, n),
    0x2578: (n, n, h, l), 0x2579: (l, h, n, n), 0x257A: (n, n, l, h), 0x257B: (h, l, n, n),
    0x257C: (n, n, l, d), 0x257D: (l, d, n, n), 0x257E: (n, n, d, l), 0x257F: (d, l, n, n),
  ]
  for (codepoint, arms) in boxArms {
    var canvas = Canvas()
    Box.arm(&canvas, direction: .up, stroke: arms.up)
    Box.arm(&canvas, direction: .down, stroke: arms.down)
    Box.arm(&canvas, direction: .left, stroke: arms.left)
    Box.arm(&canvas, direction: .right, stroke: arms.right)
    out[codepoint] = canvas.glyph
  }

  out[0x2554] = Box.doubleCorner(down: true, right: true).glyph  // ╔
  out[0x2557] = Box.doubleCorner(down: true, right: false).glyph  // ╗
  out[0x255A] = Box.doubleCorner(down: false, right: true).glyph  // ╚
  out[0x255D] = Box.doubleCorner(down: false, right: false).glyph  // ╝
  out[0x256D] = Box.roundedCorner(down: true, right: true).glyph  // ╭
  out[0x256E] = Box.roundedCorner(down: true, right: false).glyph  // ╮
  out[0x256F] = Box.roundedCorner(down: false, right: false).glyph  // ╯
  out[0x2570] = Box.roundedCorner(down: false, right: true).glyph  // ╰

  var slashForward = Canvas()
  slashForward.line(0, Canvas.height - 1, Canvas.width - 1, 0)
  out[0x2571] = slashForward.glyph  // ╱
  var slashBack = Canvas()
  slashBack.line(0, 0, Canvas.width - 1, Canvas.height - 1)
  out[0x2572] = slashBack.glyph  // ╲
  var diagonalCross = Canvas()
  diagonalCross.line(0, 0, Canvas.width - 1, Canvas.height - 1)
  diagonalCross.line(0, Canvas.height - 1, Canvas.width - 1, 0)
  out[0x2573] = diagonalCross.glyph  // ╳

  // MARK: Block elements (U+2580–259F)
  func block(_ codepoint: UInt32, rows: ClosedRange<Int>? = nil, cols: ClosedRange<Int>? = nil) {
    var canvas = Canvas()
    if let rows { canvas.fillRect(0, rows.lowerBound, Canvas.width - 1, rows.upperBound) }
    if let cols { canvas.fillRect(cols.lowerBound, 0, cols.upperBound, Canvas.height - 1) }
    out[codepoint] = canvas.glyph
  }
  block(0x2580, rows: 0...13)  // ▀ upper half
  block(0x2581, rows: 24...27)  // ▁ lower 1/8
  block(0x2582, rows: 21...27)  // ▂
  block(0x2583, rows: 17...27)  // ▃
  block(0x2584, rows: 14...27)  // ▄ lower half
  block(0x2585, rows: 10...27)  // ▅
  block(0x2586, rows: 7...27)  // ▆
  block(0x2587, rows: 3...27)  // ▇
  block(0x2588, rows: 0...27)  // █ full
  block(0x2589, cols: 0...16)  // ▉ left 7/8
  block(0x258A, cols: 0...14)  // ▊
  block(0x258B, cols: 0...11)  // ▋
  block(0x258C, cols: 0...9)  // ▌ left half
  block(0x258D, cols: 0...6)  // ▍
  block(0x258E, cols: 0...4)  // ▎
  block(0x258F, cols: 0...1)  // ▏ left 1/8
  block(0x2590, cols: 10...19)  // ▐ right half
  block(0x2594, rows: 0...3)  // ▔ upper 1/8
  block(0x2595, cols: 18...19)  // ▕ right 1/8

  // Shades ░▒▓ as ordered dithers at 25/50/75% coverage.
  let shades: [(codepoint: UInt32, keep: (Int, Int) -> Bool)] = [
    (0x2591, { x, y in (x % 2 == 0 && y % 4 == 0) || (x % 2 == 1 && y % 4 == 2) }),
    (0x2592, { x, y in (x + y) % 2 == 0 }),
    (0x2593, { x, y in !((x % 2 == 0 && y % 4 == 2) || (x % 2 == 1 && y % 4 == 0)) }),
  ]
  for (codepoint, keep) in shades {
    var canvas = Canvas()
    for y in 0..<Canvas.height {
      for x in 0..<Canvas.width where keep(x, y) { canvas.set(x, y) }
    }
    out[codepoint] = canvas.glyph
  }

  // Quadrants.
  func quadrants(_ codepoint: UInt32, upperLeft: Bool, upperRight: Bool, lowerLeft: Bool, lowerRight: Bool) {
    var canvas = Canvas()
    if upperLeft { canvas.fillRect(0, 0, 9, 13) }
    if upperRight { canvas.fillRect(10, 0, 19, 13) }
    if lowerLeft { canvas.fillRect(0, 14, 9, 27) }
    if lowerRight { canvas.fillRect(10, 14, 19, 27) }
    out[codepoint] = canvas.glyph
  }
  quadrants(0x2596, upperLeft: false, upperRight: false, lowerLeft: true, lowerRight: false)  // ▖
  quadrants(0x2597, upperLeft: false, upperRight: false, lowerLeft: false, lowerRight: true)  // ▗
  quadrants(0x2598, upperLeft: true, upperRight: false, lowerLeft: false, lowerRight: false)  // ▘
  quadrants(0x2599, upperLeft: true, upperRight: false, lowerLeft: true, lowerRight: true)  // ▙
  quadrants(0x259A, upperLeft: true, upperRight: false, lowerLeft: false, lowerRight: true)  // ▚
  quadrants(0x259B, upperLeft: true, upperRight: true, lowerLeft: true, lowerRight: false)  // ▛
  quadrants(0x259C, upperLeft: true, upperRight: true, lowerLeft: false, lowerRight: true)  // ▜
  quadrants(0x259D, upperLeft: false, upperRight: true, lowerLeft: false, lowerRight: false)  // ▝
  quadrants(0x259E, upperLeft: false, upperRight: true, lowerLeft: true, lowerRight: false)  // ▞
  quadrants(0x259F, upperLeft: false, upperRight: true, lowerLeft: true, lowerRight: true)  // ▟

  // MARK: Braille patterns (U+2800–28FF): 2×4 dot grid, used by spinners.
  for pattern in 0...255 {
    var canvas = Canvas()
    let dots: [(column: Int, row: Int)] = [
      (0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3),
    ]
    for (bit, dot) in dots.enumerated() where pattern & (1 << bit) != 0 {
      let x = 5 + dot.column * 8
      let y = 5 + dot.row * 6
      canvas.fillRect(x, y, x + 2, y + 2)
    }
    out[0x2800 + UInt32(pattern)] = canvas.glyph
  }

  // MARK: Punctuation and symbols
  var enDash = Canvas()
  enDash.fillRect(4, 13, 15, 14)
  out[0x2013] = enDash.glyph  // –
  var emDash = Canvas()
  emDash.fillRect(1, 13, 18, 14)
  out[0x2014] = emDash.glyph  // —

  for codepoint in [UInt32(0x2018), UInt32(0x2019)] {  // ' '
    var canvas = Canvas()
    canvas.fillRect(9, 5, 10, 8)
    canvas.set(8, 9)
    out[codepoint] = canvas.glyph
  }
  for codepoint in [UInt32(0x201C), UInt32(0x201D)] {  // " "
    var canvas = Canvas()
    canvas.fillRect(6, 5, 7, 8)
    canvas.fillRect(12, 5, 13, 8)
    canvas.set(5, 9)
    canvas.set(11, 9)
    out[codepoint] = canvas.glyph
  }

  var ellipsis = Canvas()
  for centerX in [3, 9, 15] { ellipsis.fillRect(centerX, 13, centerX + 1, 14) }
  out[0x2026] = ellipsis.glyph  // …

  var middleDot = Canvas()
  middleDot.disc(centerX: 10, centerY: 14, radius: 2)
  out[0x00B7] = middleDot.glyph  // ·
  var bullet = Canvas()
  bullet.disc(centerX: 10, centerY: 14, radius: 3.5)
  out[0x2022] = bullet.glyph  // •

  var multiply = Canvas()
  multiply.line(4, 8, 15, 20)
  multiply.line(15, 8, 4, 20)
  out[0x00D7] = multiply.glyph  // ×
  out[0x2715] = multiply.glyph  // ✕
  out[0x2716] = multiply.glyph  // ✖
  out[0x2717] = multiply.glyph  // ✗ (oh-my-zsh dirty-repo marker)

  var check = Canvas()
  check.line(3, 15, 8, 21)
  check.line(8, 21, 17, 7)
  out[0x2713] = check.glyph  // ✓
  out[0x2714] = check.glyph  // ✔

  // MARK: Arrows
  var rightArrow = Canvas()
  rightArrow.fillRect(1, 13, 15, 14)
  rightArrow.line(11, 7, 18, 14)
  rightArrow.line(11, 21, 18, 14)
  out[0x2192] = rightArrow.glyph  // →
  var leftArrow = rightArrow
  leftArrow.flipHorizontally()
  out[0x2190] = leftArrow.glyph  // ←
  var upArrow = Canvas()
  upArrow.fillRect(9, 4, 10, 25)
  upArrow.line(3, 11, 10, 3)
  upArrow.line(16, 11, 9, 3)
  out[0x2191] = upArrow.glyph  // ↑
  var downArrow = Canvas()
  downArrow.fillRect(9, 2, 10, 23)
  downArrow.line(3, 17, 10, 25)
  downArrow.line(16, 17, 9, 25)
  out[0x2193] = downArrow.glyph  // ↓

  var heavyArrow = Canvas()
  heavyArrow.fillRect(1, 12, 11, 15)
  for x in 10...18 {
    let half = Int((Double(x - 10) / 8.0) * 7.5 + 0.5)
    heavyArrow.fillRect(x, 14 - half, x, 13 + half)
  }
  out[0x279C] = heavyArrow.glyph  // ➜ (oh-my-zsh robbyrussell prompt)

  // MARK: Geometric shapes
  var blackCircle = Canvas()
  blackCircle.disc(centerX: 10, centerY: 14, radius: 6)
  out[0x25CF] = blackCircle.glyph  // ●
  var whiteCircle = Canvas()
  whiteCircle.ring(centerX: 10, centerY: 14, radius: 6, thickness: 2)
  out[0x25CB] = whiteCircle.glyph  // ○
  var whiteBullet = Canvas()
  whiteBullet.ring(centerX: 10, centerY: 14, radius: 3.5, thickness: 1.5)
  out[0x25E6] = whiteBullet.glyph  // ◦
  var smallSquare = Canvas()
  smallSquare.fillRect(7, 11, 12, 17)
  out[0x25AA] = smallSquare.glyph  // ▪
  out[0x25AB] = smallSquare.glyph  // ▫

  var upTriangle = Canvas()
  upTriangle.triangleUp(centerX: 10, top: 7, bottom: 21, halfWidth: 8)
  out[0x25B2] = upTriangle.glyph  // ▲
  var downTriangle = Canvas()
  for y in 7...21 {
    let half = Int((Double(21 - y) / 14.0) * 8 + 0.5)
    downTriangle.fillRect(10 - half, y, 10 + half, y)
  }
  out[0x25BC] = downTriangle.glyph  // ▼
  var smallRightTriangle = Canvas()
  for y in 9...19 {
    let half = max(0, 5 - Int((Double(abs(y - 14)) / 5.5) * 5 + 0.5))
    smallRightTriangle.fillRect(6, y, 6 + half + 3, y)
  }
  out[0x25B8] = smallRightTriangle.glyph  // ▸
  var smallDownTriangle = Canvas()
  for y in 9...19 {
    let half = Int((Double(19 - y) / 10.0) * 5 + 0.5)
    smallDownTriangle.fillRect(10 - half, y, 10 + half, y)
  }
  out[0x25BE] = smallDownTriangle.glyph  // ▾

  var leftTriangle = Canvas()
  for x in 2...17 {
    let half = Int((Double(17 - x) / 15.0) * 7 + 0.5)
    leftTriangle.fillRect(x, 14 - half, x, 13 + half)
  }
  out[0x25C0] = leftTriangle.glyph  // ◀
  var rightTriangle = leftTriangle
  rightTriangle.flipHorizontally()
  out[0x25B6] = rightTriangle.glyph  // ▶

  var diamond = Canvas()
  for y in 6...22 {
    let half = max(0, Int((1.0 - abs(Double(y) - 14.0) / 8.0) * 7 + 0.5))
    diamond.fillRect(10 - half, y, 10 + half, y)
  }
  out[0x25C6] = diamond.glyph  // ◆

  var whiteDiamond = Canvas()
  whiteDiamond.line(10, 5, 18, 14)
  whiteDiamond.line(18, 14, 10, 23)
  whiteDiamond.line(10, 23, 2, 14)
  whiteDiamond.line(2, 14, 10, 5)
  out[0x25C7] = whiteDiamond.glyph  // ◇

  var blackSquare = Canvas()
  blackSquare.fillRect(4, 8, 16, 20)
  out[0x25A0] = blackSquare.glyph  // ■

  var pencil = Canvas()
  pencil.line(4, 21, 15, 7, thickness: 3)
  pencil.line(6, 23, 17, 9, thickness: 3)
  pencil.line(15, 7, 17, 9, thickness: 3)
  pencil.line(4, 21, 6, 23, thickness: 3)
  pencil.set(3, 24)
  out[0x270E] = pencil.glyph  // ✎ lower-right pencil

  // MARK: Keyboard and interface symbols
  // These are common in shortcut labels and native macOS interfaces. Keeping
  // them in the bitmap atlas lets clients use concise labels without getting a
  // replacement box on non-AppKit renderers.
  var command = Canvas()
  command.ring(centerX: 6, centerY: 9, radius: 4, thickness: 2)
  command.ring(centerX: 14, centerY: 9, radius: 4, thickness: 2)
  command.ring(centerX: 6, centerY: 19, radius: 4, thickness: 2)
  command.ring(centerX: 14, centerY: 19, radius: 4, thickness: 2)
  command.fillRect(6, 8, 14, 10)
  command.fillRect(6, 18, 14, 20)
  command.fillRect(5, 9, 7, 19)
  command.fillRect(13, 9, 15, 19)
  out[0x2318] = command.glyph  // ⌘

  var home = Canvas()
  home.line(2, 14, 10, 6)
  home.line(10, 6, 18, 14)
  home.line(4, 12, 4, 23)
  home.line(4, 23, 16, 23)
  home.line(16, 23, 16, 12)
  home.line(8, 23, 8, 17)
  home.line(8, 17, 12, 17)
  home.line(12, 17, 12, 23)
  out[0x2302] = home.glyph  // ⌂

  var returnArrow = Canvas()
  returnArrow.fillRect(5, 13, 17, 15)
  returnArrow.fillRect(15, 7, 17, 15)
  returnArrow.line(5, 14, 10, 9, thickness: 2)
  returnArrow.line(5, 14, 10, 19, thickness: 2)
  out[0x21B5] = returnArrow.glyph  // ↵
  out[0x23CE] = returnArrow.glyph  // ⏎

  var option = Canvas()
  option.fillRect(2, 7, 7, 9)
  option.line(7, 8, 13, 20, thickness: 2)
  option.fillRect(13, 19, 18, 21)
  option.fillRect(12, 7, 18, 9)
  out[0x2325] = option.glyph  // ⌥

  var control = Canvas()
  control.line(4, 17, 10, 10, thickness: 2)
  control.line(10, 10, 16, 17, thickness: 2)
  out[0x2303] = control.glyph  // ⌃

  var shift = Canvas()
  shift.line(3, 14, 10, 6, thickness: 2)
  shift.line(10, 6, 17, 14, thickness: 2)
  shift.line(3, 14, 7, 14, thickness: 2)
  shift.fillRect(7, 14, 7, 22)
  shift.fillRect(7, 22, 13, 22)
  shift.fillRect(13, 14, 13, 22)
  shift.fillRect(13, 14, 17, 14)
  out[0x21E7] = shift.glyph  // ⇧

  var play = Canvas()
  for x in 4...16 {
    let half = Int((Double(x - 4) / 12.0) * 8 + 0.5)
    play.fillRect(x, 14 - half, x, 14 + half)
  }
  out[0x23F5] = play.glyph  // ⏵
  var stop = Canvas()
  stop.fillRect(4, 8, 16, 20)
  out[0x23F9] = stop.glyph  // ⏹

  // MARK: Common Nerd Font symbols used by LazyVim and terminal prompts
  // These remain native 20×28 bitmaps in each graphical backend's atlas; no
  // system font is consulted at build time or runtime.
  var search = Canvas()
  search.ring(centerX: 8, centerY: 10, radius: 6, thickness: 2)
  search.line(12, 15, 18, 22, thickness: 3)
  out[0xF002] = search.glyph  //  find/search

  var file = Canvas()
  file.line(5, 3, 13, 3)
  file.line(5, 3, 5, 24)
  file.line(5, 24, 16, 24)
  file.line(16, 10, 16, 24)
  file.line(13, 3, 16, 10)
  file.line(13, 3, 13, 10)
  file.line(13, 10, 16, 10)
  out[0xF15B] = file.glyph  //  new file

  var list = Canvas()
  for y in [7, 14, 21] {
    list.fillRect(2, y - 1, 4, y + 1)
    list.fillRect(7, y - 1, 18, y + 1)
  }
  out[0xF022] = list.glyph  //  find text/list

  var copy = Canvas()
  copy.line(3, 4, 13, 4)
  copy.line(3, 4, 3, 20)
  copy.line(3, 20, 13, 20)
  copy.line(13, 4, 13, 20)
  copy.line(7, 8, 17, 8)
  copy.line(17, 8, 17, 24)
  copy.line(7, 24, 17, 24)
  out[0xF0C5] = copy.glyph  //  recent files/copy

  var gear = Canvas()
  gear.ring(centerX: 10, centerY: 14, radius: 7, thickness: 3)
  gear.disc(centerX: 10, centerY: 14, radius: 2)
  for (x, y) in [(9, 2), (9, 23), (0, 13), (17, 13), (2, 5), (15, 20), (15, 5), (2, 20)] {
    gear.fillRect(x, y, x + 2, y + 2)
  }
  out[0xF423] = gear.glyph  //  config

  var history = Canvas()
  history.ring(centerX: 10, centerY: 14, radius: 8, thickness: 2)
  history.line(10, 14, 10, 7)
  history.line(10, 14, 15, 17)
  history.line(1, 6, 1, 13, thickness: 2)
  history.line(1, 6, 7, 6, thickness: 2)
  out[0xE348] = history.glyph  //  restore session

  var sparkle = Canvas()
  sparkle.line(10, 3, 10, 25)
  sparkle.line(2, 14, 18, 14)
  sparkle.line(5, 7, 15, 21)
  sparkle.line(15, 7, 5, 21)
  out[0xEACC] = sparkle.glyph  //  extras

  // Visible fallback for unsupported scalars. The old fallback was U+0020,
  // silently turning every unknown glyph into whitespace and making correct
  // terminal columns look like broken spacing.
  var replacement = Canvas()
  replacement.line(3, 3, 16, 3)
  replacement.line(16, 3, 16, 24)
  replacement.line(16, 24, 3, 24)
  replacement.line(3, 24, 3, 3)
  replacement.line(7, 9, 10, 6)
  replacement.line(10, 6, 13, 9)
  replacement.line(13, 9, 10, 14)
  replacement.fillRect(9, 19, 11, 21)
  out[0xFFFD] = replacement.glyph

  // MARK: Powerline separators (U+E0B0–E0BF common subset)
  var powerRight = Canvas()
  for y in 0..<Canvas.height {
    let width = max(0, Int((1.0 - abs(Double(y) + 0.5 - 14.0) / 14.0) * 19 + 0.5))
    powerRight.fillRect(0, y, width, y)
  }
  out[0xE0B0] = powerRight.glyph  // right filled triangle
  var powerLeft = powerRight
  powerLeft.flipHorizontally()
  out[0xE0B2] = powerLeft.glyph  // left filled triangle
  var powerRightThin = Canvas()
  powerRightThin.line(0, 0, 19, 14)
  powerRightThin.line(0, 27, 19, 14)
  out[0xE0B1] = powerRightThin.glyph  // right thin triangle
  var powerLeftThin = powerRightThin
  powerLeftThin.flipHorizontally()
  out[0xE0B3] = powerLeftThin.glyph  // left thin triangle
  var powerCircleRight = Canvas()
  for y in 0..<Canvas.height {
    let dy = Double(y) + 0.5 - 14.0
    let span = (14.0 * 14.0 - dy * dy).squareRoot()
    if span > 0 { powerCircleRight.fillRect(0, y, Int(span), y) }
  }
  out[0xE0B4] = powerCircleRight.glyph  // right half-disc
  var powerCircleLeft = powerCircleRight
  powerCircleLeft.flipHorizontally()
  out[0xE0B6] = powerCircleLeft.glyph  // left half-disc
  var powerDiagonalLeft = Canvas()
  for y in 0..<Canvas.height {
    let width = max(0, Int((Double(Canvas.height - 1 - y) / 27.0) * 19 + 0.5))
    powerDiagonalLeft.fillRect(0, y, width, y)
  }
  out[0xE0B8] = powerDiagonalLeft.glyph  // lower-left diagonal
  var powerDiagonalRight = powerDiagonalLeft
  powerDiagonalRight.flipHorizontally()
  out[0xE0BA] = powerDiagonalRight.glyph  // lower-right diagonal

  return out
}
