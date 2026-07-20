import Foundation
import Chroma

#if METAL_BACKEND
import MetalBackend
typealias PlatformApp = MetalApp
#elseif WAYLAND_BACKEND
import WaylandBackend
typealias PlatformApp = WaylandApp
#else
#error(
  "ChromaDemo requires a rendering backend: MetalBackend (enabled by default) or WaylandBackend."
)
#endif

@main
struct ChromaDemo: PlatformApp {
  var title: String { "Chroma Demo" }

  var body: some Block {
    Entry()
  }
}

private struct Entry: Block {
  let theme = Theme()

  var body: some Block {
    VStack(spacing: 0) {
      Header(theme: theme)
      HStack(spacing: theme.margin) {
        Sidebar(theme: theme)
          .frame(width: 300)
        AsciiPanel(theme: theme)
          .background(theme.panelBackground)
          .border(theme.border, width: 1)
      }
      .padding(theme.margin)
      StatusBar(theme: theme)
    }
    .background(theme.background)
  }
}

private struct Header: Block {
  let theme: Theme

  var body: some Block {
    VStack(spacing: 0) {
      Text("Chroma  —  Immediate-Mode GUI Demo")
        .fontScale(theme.textScale)
        .foregroundColor(theme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(EdgeInsets(leading: theme.margin))
      theme.borderAccent
        .frame(height: 1)
    }
    .frame(height: theme.headerHeight)
    .background(theme.headerBackground)
  }
}

private struct StatusBar: Block {
  let theme: Theme

  var body: some Block {
    VStack(spacing: 0) {
      theme.borderAccent
        .frame(height: 1)
      Text("FPS: --")
        .fontScale(theme.textScale)
        .foregroundColor(theme.green)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(EdgeInsets(leading: theme.margin))
    }
    .frame(height: theme.statusHeight)
    .background(theme.statusBackground)
  }
}

private struct Sidebar: Block {
  let theme: Theme

  var body: some Block {
    VStack(spacing: theme.spacing, alignment: .leading) {
      SectionTitle(title: "CONTROLS", theme: theme)
      DemoButton(label: "New Project", theme: theme)
      DemoButton(label: "Open...", theme: theme)
      DemoButton(label: "Save", theme: theme)

      Spacer().frame(height: theme.spacing)
      SectionTitle(title: "OPTIONS", theme: theme)
      CheckRow(label: "Wireframe", checked: true, theme: theme)
      CheckRow(label: "Grid", checked: true, theme: theme)
      CheckRow(label: "Axis", checked: false, theme: theme)
      CheckRow(label: "Stats", checked: true, theme: theme)

      Spacer().frame(height: theme.spacing)
      SectionTitle(title: "COLORS", theme: theme)
      SwatchGrid(theme: theme)
    }
    .padding(theme.panelPadding)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(theme.panelBackground)
    .border(theme.border, width: 1)
  }
}

private struct SectionTitle: Block {
  let title: String
  let theme: Theme

  var body: some Block {
    Text(title)
      .fontScale(theme.textScale)
      .foregroundColor(theme.textSecondary)
      .frame(height: theme.itemHeight, alignment: .leading)
      .padding(EdgeInsets(bottom: theme.spacing))
  }
}

private struct DemoButton: Block {
  let label: String
  let theme: Theme

  var body: some Block {
    Text(label)
      .fontScale(theme.textScale)
      .foregroundColor(.white)
      .padding(EdgeInsets(leading: 12))
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: theme.itemHeight, alignment: .leading)
      .background(theme.buttonIdle)
      .border(theme.border, width: 1)
  }
}

private struct CheckRow: Block {
  let label: String
  let checked: Bool
  let theme: Theme

  var body: some Block {
    HStack(spacing: 10, alignment: .center) {
      ZStack {
        checked ? theme.accent : theme.buttonIdle
        if checked {
          Text("+")
            .fontScale(theme.textScale)
            .foregroundColor(.white)
        }
      }
      .frame(width: 24, height: 24)
      .border(checked ? theme.accent : theme.border, width: 1)

      Text(label)
        .fontScale(theme.textScale)
        .foregroundColor(.white)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: theme.itemHeight, alignment: .leading)
  }
}

private struct SwatchGrid: Block {
  let theme: Theme

  var body: some Block {
    VStack(spacing: 12, alignment: .leading) {
      HStack(spacing: 16) {
        Swatch(label: "Blue", color: theme.accent, theme: theme)
        Swatch(label: "Green", color: theme.green, theme: theme)
        Swatch(label: "Red", color: theme.red, theme: theme)
      }
      HStack(spacing: 16) {
        Swatch(label: "Yellow", color: theme.yellow, theme: theme)
        Swatch(label: "Orange", color: theme.orange, theme: theme)
        Swatch(label: "Purple", color: theme.purple, theme: theme)
      }
    }
  }
}

private struct Swatch: Block {
  let label: String
  let color: Color
  let theme: Theme

  var body: some Block {
    VStack(spacing: 6, alignment: .leading) {
      color
        .frame(width: 30, height: 30)
        .border(theme.border, width: 1)
      Text(label)
        .fontScale(theme.textScale)
        .foregroundColor(theme.textSecondary)
    }
  }
}

private struct AsciiPanel: PrimitiveBlock {
  let theme: Theme

  var expandsHorizontally: Bool { true }
  var expandsVertically: Bool { true }

  func sizeThatFits(_ proposal: Size) -> Size { proposal }

  func draw(into drawList: inout DrawList, in rect: Rect) {
    let printableRows: [[UInt8]] = stride(from: 0x20, through: 0x70, by: 0x10).map { first in
      let last = min(first + 0x0f, 0x7e)
      return Array(String(format: "%02X  ", first).utf8) + (first...last).map(UInt8.init)
    }
    let lines = [Array("5x7  PRINTABLE  ASCII  20..7E".utf8)] + printableRows

    // Fit the specimen to the assigned rect with an integer text scale.
    let metrics = FontMetrics()
    let availableWidth = rect.size.width - 2 * theme.panelPadding
    let availableHeight = rect.size.height - 2 * theme.panelPadding
    let longestLine = Float(lines.map(\.count).max() ?? 1)
    let widthScale = availableWidth / (longestLine * metrics.cellAdvance)
    let heightScale = availableHeight / (Float(lines.count) * metrics.lineAdvance)
    let scale = max(1, min(3, floor(min(widthScale, heightScale))))

    for (row, bytes) in lines.enumerated() {
      drawList.text(
        String(decoding: bytes, as: UTF8.self),
        at: Point(
          x: rect.minX + theme.panelPadding,
          y: rect.minY + theme.panelPadding + Float(row) * metrics.lineAdvance * scale
        ),
        color: row == 0 ? theme.yellow : .white,
        scale: scale
      )
    }
  }
}

private struct Theme {
  var margin: Float = 16
  var spacing: Float = 10
  var panelPadding: Float = 16
  var headerHeight: Float = 48
  var statusHeight: Float = 32
  var itemHeight: Float = 36
  var textScale: Float = 2

  var background = Color(r: 0.08, g: 0.09, b: 0.13, a: 1)
  var panelBackground = Color(r: 0.10, g: 0.11, b: 0.16, a: 1)
  var headerBackground = Color(r: 0.12, g: 0.14, b: 0.22, a: 1)
  var statusBackground = Color(r: 0.06, g: 0.20, b: 0.12, a: 1)
  var border = Color(r: 0.22, g: 0.22, b: 0.32, a: 1)
  var borderAccent = Color(r: 0.28, g: 0.44, b: 0.72, a: 1)
  var buttonIdle = Color(r: 0.18, g: 0.20, b: 0.30, a: 1)
  var textSecondary = Color(r: 0.5, g: 0.5, b: 0.6, a: 1)
  var accent = Color(r: 0.3, g: 0.6, b: 1.0, a: 1)
  var green = Color(r: 0.3, g: 0.8, b: 0.4, a: 1)
  var red = Color(r: 0.9, g: 0.3, b: 0.3, a: 1)
  var yellow = Color(r: 1, g: 0.85, b: 0.25, a: 1)
  var orange = Color(r: 1, g: 0.55, b: 0.15, a: 1)
  var purple = Color(r: 0.7, g: 0.3, b: 0.9, a: 1)
}
