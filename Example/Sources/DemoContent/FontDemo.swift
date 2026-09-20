import Chroma

struct FontDemo: Block {
  let state: PerformanceDemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 12) {
        HStack(spacing: 8) {
          Text("BUNDLED MONOSPACE FONT").fontScale(0.7).foregroundColor(theme.accent)
          Spacer()
          Button("-", fontScale: 0.55) {
            state.fontScale = max(0.5, state.fontScale - 0.25)
          }
          Text("\(Int(state.fontScale * 100))%").fontScale(0.55)
          Button("+", fontScale: 0.55) {
            state.fontScale = min(1.5, state.fontScale + 0.25)
          }
        }
        HStack(spacing: 16) {
          ScrollView {
            VStack(spacing: 16) {
              VStack(spacing: 8) {
                heading("LIVE PREVIEW")
                TextField(
                  "Type a sample", fontScale: 0.65,
                  text: { state.fontSample }, onChange: { state.fontSample = $0 })
                Text(state.fontSample).fontScale(state.fontScale)
                  .selectable()
                  .clipped()
              }
              .padding(12).background(theme.surface)
              VStack(spacing: 8) {
                heading("GLYPH EXPLORER / CLICK A CELL")
                GlyphExplorer(state: state)
              }
              .padding(12).background(theme.surface)
              VStack(spacing: 8) {
                heading("CANONICAL EQUIVALENCE")
                HStack(spacing: 24) {
                  comparison("BASE / U+0065", "e")
                  comparison("U+00E9", "é")
                  comparison("U+0065 + U+0301", "e\u{0301}")
                }
                Text("The two accented cells should match exactly.").fontScale(0.5)
              }
              .padding(12).background(theme.surface)
              VStack(spacing: 8) {
                heading("TERMINAL / CONTIGUOUS 12 x 28 CELLS")
                TerminalSpecimen().sizing(y: .fixed(84))
              }
              .padding(12).background(theme.surface)
              VStack(spacing: 8) {
                heading("KNOWN LIMITS / EXPECTED REPLACEMENT GLYPHS")
                Text("🙂  👩‍💻  e\u{0301}\u{0308}  �").fontScale(0.9)
                Text("Emoji and stacked accents are not supported yet.").fontScale(0.5)
              }
              .padding(12).background(theme.surface)
            }
          }.sizing(x: .grow, y: .grow)
          VStack(spacing: 12) {
            heading("CELL INSPECTOR")
            GlyphInspection(glyph: state.inspectedGlyph)
              .sizing(y: .fixed(240))
            Text(
              state.inspectedGlyph.unicodeScalars.map {
                "U+" + String($0.value, radix: 16, uppercase: true).leftPaddedToFour
              }.joined(separator: " ")
            ).fontScale(0.65)
            Text("BUNDLED FONT / \(Int(FontMetrics().cellAdvance)) PT ADVANCE").fontScale(0.5)
            Text("Blue: advance boundary").fontScale(0.5)
            Text("Gray: 20 x 28 glyph canvas").fontScale(0.5)
            Text("8x magnification").fontScale(0.5)
            Spacer()
          }
          .padding(12).sizing(x: .fixed(270), y: .grow).background(theme.surface)
        }.sizing(x: .grow, y: .grow)
      }.padding(12).background(theme.background)
    }
  }

  private func heading(_ text: String) -> Text {
    Text(text).fontScale(0.5).foregroundColor(Color(r: 0.2, g: 0.65, b: 1, a: 1))
  }

  @MainActor private func comparison(_ label: String, _ sample: String) -> some Block {
    VStack(spacing: 4) {
      Text(label).fontScale(0.4)
      Text(sample).fontScale(1.5)
    }
  }
}

extension String {
  fileprivate var leftPaddedToFour: String { String(repeating: "0", count: max(0, 4 - count)) + self }
}

struct GlyphExplorer: PrimitiveBlock {
  let state: PerformanceDemoState
  static let glyphs = Array(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!?@#$%&*()[]{}ÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜàáâãäåèéêëìíîïòóôõöùúûüÇçÑñÝýÿČčŠšŽžĀāĂăĄą"
  )
  private let cell: Float = 40

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let columns = max(1, Int(proposal.width / cell))
    return Size(width: proposal.width, height: Float((Self.glyphs.count + columns - 1) / columns) * cell)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let columns = max(1, Int(rect.size.width / cell))
    let rows = (Self.glyphs.count + columns - 1) / columns
    context.withFocusGroup(in: rect, axis: .vertical) {
      for row in 0..<rows {
        let rowRect = Rect(
          x: rect.minX, y: rect.minY + Float(row) * cell, width: rect.size.width, height: cell)
        context.withFocusGroup(in: rowRect, axis: .horizontal) {
          for column in 0..<columns {
            let index = row * columns + column
            guard index < Self.glyphs.count else { break }
            let box = Rect(
              x: rowRect.minX + Float(column) * cell, y: rowRect.minY, width: cell, height: cell)
            let text = String(Self.glyphs[index])
            _ = context.childScope(index).buttonState(in: box, role: .normal) {
              state.inspectedGlyph = text
            }
            if state.inspectedGlyph == text { drawList.fillRect(box, color: context.theme.elevatedSurface) }
            drawList.strokeRect(box, width: 0.5, color: context.theme.border)
            drawList.text(
              text, at: Point(x: box.minX + 10, y: box.minY + 6),
              color: state.inspectedGlyph == text ? context.theme.accent : context.theme.foreground)
          }
        }
      }
    }
  }
}

struct GlyphInspection: PrimitiveBlock {
  let glyph: String

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Size(width: 200, height: 240)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let origin = Point(x: rect.minX + 16, y: rect.minY + 8)
    for column in 0...20 {
      drawList.fillRect(
        Rect(x: origin.x + Float(column) * 8, y: origin.y, width: 0.5, height: 224), color: context.theme.border)
    }
    for row in 0...28 {
      drawList.fillRect(
        Rect(x: origin.x, y: origin.y + Float(row) * 8, width: 160, height: 0.5), color: context.theme.border)
    }
    drawList.text(glyph, at: origin, color: context.theme.foreground, scale: 8)
    drawList.strokeRect(
      Rect(origin: origin, size: Size(width: 160, height: 224)), width: 1, color: context.theme.secondaryForeground)
    drawList.fillRect(
      Rect(
        x: origin.x + context.fontMetrics.cellAdvance * 8,
        y: origin.y, width: 1, height: 224), color: context.theme.accent)
  }
}

struct TerminalSpecimen: PrimitiveBlock {
  static let rows = ["╭────╮ ┌────┐ ░▒▓█", "│    │ │    │ ←↑→↓", "╰────╯ └────┘ ⠁⠃⠇⠏"]

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Size(width: 360, height: 84)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    for (row, text) in Self.rows.enumerated() {
      drawList.text(
        text, at: Point(x: rect.minX, y: rect.minY + Float(row) * 28),
        color: context.theme.foreground)
    }
  }
}
