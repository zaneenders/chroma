import Chroma
import Foundation

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
  var title: String { "Chroma" }
  var windowSize: Size { Size(width: 1040, height: 720) }

  private let state = DemoState()

  var body: some Block {
    Entry(theme: Theme(), state: state)
  }
}

/// The demo's application state, shared by reference so value-type blocks can
/// read it every frame and interaction closures can mutate it.
private enum DemoTab {
  case package
  case ascii
}

private final class DemoState {
  var selectedTab: DemoTab = .package
  let packageSource = DemoState.loadPackageSource()
  let packageScrollController = ScrollViewController()
  var accent = Color(r: 0.20, g: 0.62, b: 0.98, a: 1)
  var accentName = "Blue"
  var wireframe = false
  var grid = true
  var axis = false
  var stats = true
  var name = ""
  var lastAction = "None"
  var actionCount = 0

  func record(_ action: String) {
    lastAction = action
    actionCount += 1
  }

  private static func loadPackageSource() -> String {
    let packageURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Package.swift")
    return (try? String(contentsOf: packageURL, encoding: .utf8))
      ?? "Could not load \(packageURL.path)"
  }
}

private struct Entry: Block {
  let theme: Theme
  let state: DemoState

  var body: some Block {
    VStack(spacing: 0) {
      Header(theme: theme, state: state)
      HStack(spacing: theme.margin) {
        Sidebar(theme: theme, state: state)
          .frame(width: 248, alignment: .topLeading)
        MainPanel(theme: theme, state: state)
      }
      .padding(theme.margin)
      StatusBar(theme: theme, state: state)
    }
    .background(theme.background)
  }
}

private struct Header: Block {
  let theme: Theme
  let state: DemoState

  var body: some Block {
    VStack(spacing: 0) {
      Text(
        state.name.isEmpty
          ? "CHROMA  /  WORKBENCH"
          : "CHROMA  /  HELLO \(state.name.uppercased())"
      )
      .fontScale(theme.textScale)
      .foregroundColor(state.accent)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(EdgeInsets(leading: theme.margin))
      state.accent
        .frame(height: 1)
    }
    .frame(height: theme.headerHeight)
    .background(theme.headerBackground)
  }
}

private struct StatusBar: Block {
  let theme: Theme
  let state: DemoState

  @MainActor var body: some Block {
    let interaction = Interaction.current
    let fps = Int(interaction.frameRate.rounded())
    return VStack(spacing: 0) {
      state.accent
        .frame(height: 1)
      HStack(spacing: 0) {
        if state.stats {
          Text(interaction.isTextEditing ? "INSERT" : "NAV")
            .fontScale(theme.textScale)
            .foregroundColor(interaction.isTextEditing ? theme.yellow : theme.green)
          Text("  FPS: \(fps)")
            .fontScale(theme.textScale)
            .foregroundColor(theme.textSecondary)
          Text("  Mouse: \(interaction.lastMacroDescription)")
            .fontScale(theme.textScale)
            .foregroundColor(state.accent)
        }
        Spacer()
        Text("Last action: \(state.lastAction) (\(state.actionCount))")
          .fontScale(theme.textScale)
          .foregroundColor(theme.textSecondary)
      }
      .padding(EdgeInsets(leading: theme.margin, trailing: theme.margin))
    }
    .frame(height: theme.statusHeight)
    .background(theme.statusBackground)
  }
}

private struct Sidebar: Block {
  let theme: Theme
  let state: DemoState

  var body: some Block {
    VStack(spacing: theme.spacing, alignment: .leading) {
      SectionTitle(title: "CONTROLS", theme: theme)
      DemoButton(label: "New Project", theme: theme, accent: state.accent) {
        state.record("New Project")
      }
      DemoButton(label: "Open...", theme: theme, accent: state.accent) {
        state.record("Open...")
      }
      DemoButton(label: "Save", theme: theme, accent: state.accent) {
        state.record("Save")
      }

      Spacer().frame(height: theme.spacing)
      SectionTitle(title: "OPTIONS", theme: theme)
      CheckRow(label: "Wireframe", isOn: state.wireframe, theme: theme, accent: state.accent) {
        state.wireframe.toggle()
      }
      CheckRow(label: "Grid", isOn: state.grid, theme: theme, accent: state.accent) {
        state.grid.toggle()
      }
      CheckRow(label: "Axis", isOn: state.axis, theme: theme, accent: state.accent) {
        state.axis.toggle()
      }
      CheckRow(label: "Stats", isOn: state.stats, theme: theme, accent: state.accent) {
        state.stats.toggle()
      }

      Spacer().frame(height: theme.spacing)
      SectionTitle(title: "PROFILE", theme: theme)
      TextField(
        "your name",
        id: WidgetID("field:name"),
        fontScale: theme.textScale,
        padding: 7,
        text: { state.name },
        onChange: { state.name = $0 }
      )

      Spacer().frame(height: theme.spacing)
      SectionTitle(title: "COLORS", theme: theme)
      SwatchGrid(theme: theme, state: state)

      Spacer().frame(height: theme.spacing)
      SectionTitle(title: "KEYS", theme: theme)
      KeyLegend(theme: theme)
    }
    .padding(theme.panelPadding)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(theme.panelBackground)
    .border(theme.border, width: 1)
  }
}

private struct MainPanel: Block {
  let theme: Theme
  let state: DemoState

  var body: some Block {
    VStack(spacing: 0, alignment: .leading) {
      HStack(spacing: 0) {
        TabButton(
          label: "Package.swift",
          selected: state.selectedTab == .package,
          theme: theme,
          accent: state.accent
        ) {
          state.selectedTab = .package
          state.record("Package.swift tab")
        }
        TabButton(
          label: "ASCII Test",
          selected: state.selectedTab == .ascii,
          theme: theme,
          accent: state.accent
        ) {
          state.selectedTab = .ascii
          state.record("ASCII Test tab")
        }
        Spacer()
      }
      .frame(height: theme.itemHeight)
      .background(theme.headerBackground)

      if state.selectedTab == .package {
        PackagePanel(
          theme: theme,
          source: state.packageSource,
          scrollController: state.packageScrollController
        )
      } else {
        AsciiPanel(theme: theme, state: state)
      }
    }
    .background(theme.panelBackground)
    .border(theme.border, width: 1)
  }
}

private struct TabButton: Block {
  let label: String
  let selected: Bool
  let theme: Theme
  let accent: Color
  let action: () -> Void

  var body: some Block {
    Interactive(id: "tab:\(label)", action: action) { phase in
      Text(label)
        .fontScale(theme.textScale)
        .foregroundColor(selected ? .white : theme.textSecondary)
        .padding(EdgeInsets(leading: 12, trailing: 12))
        .frame(height: theme.itemHeight)
        .background(selected ? accent : theme.buttonColor(for: phase, accent: accent))
        .border(selected ? accent : theme.border, width: 1)
    }
  }
}

private struct PackagePanel: Block {
  let theme: Theme
  let source: String
  let scrollController: ScrollViewController

  var body: some Block {
    ScrollView(
      id: WidgetID("demo:package-scroll"),
      showsIndicator: true,
      controller: scrollController
    ) {
      VStack(spacing: theme.spacing, alignment: .leading) {
        Text("PACKAGE.SWIFT   /   UP-DOWN SELECT   /   WHEEL SCROLL")
          .fontScale(theme.textScale)
          .foregroundColor(theme.yellow)
        PackageSourceListing(
          theme: theme,
          source: source,
          scrollController: scrollController
        )
      }
      .padding(theme.panelPadding)
    }
  }
}

/// A vertically navigable source listing. Each line is a focus-tree leaf, so
/// Up/Down and pointer hover share the normal one-cursor navigation path.
private struct PackageSourceListing: PrimitiveBlock {
  let theme: Theme
  let lines: [Substring]
  let scrollController: ScrollViewController

  init(theme: Theme, source: String, scrollController: ScrollViewController) {
    self.theme = theme
    self.lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    self.scrollController = scrollController
  }

  func sizeThatFits(_ proposal: Size) -> Size {
    let metrics = FontMetrics()
    let longestLine = lines.map(\.utf8.count).max() ?? 0
    return Size(
      width: Float(longestLine + 5) * metrics.cellAdvance * theme.textScale,
      height: Float(lines.count) * metrics.lineAdvance * theme.textScale
    )
  }

  func draw(into drawList: inout DrawList, in rect: Rect) {
    let interaction = Interaction.current
    let lineHeight = FontMetrics().lineAdvance * theme.textScale
    interaction.beginGroup(.vertical, rect: rect)
    for (index, line) in lines.enumerated() {
      let lineRect = Rect(
        x: rect.minX,
        y: rect.minY + Float(index) * lineHeight,
        width: rect.size.width,
        height: lineHeight
      )
      let state = interaction.interactiveBehavior(
        id: WidgetID("package-line:\(index)"),
        rect: lineRect
      )
      if state.hovered {
        drawList.fillRect(lineRect, color: theme.buttonHover)
        // Reveal keyboard-driven selection changes, but do not enqueue a reveal
        // every frame for a stationary pointer. Repeated hover requests fight
        // wheel momentum and make vertical scrolling feel sticky.
        if !interaction.input.commands.isEmpty {
          scrollController.scrollToVisible(lineRect)
        }
      }
      let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
      drawList.text(
        String(format: "%3d  %@", index + 1, String(line)),
        at: lineRect.origin,
        color: isComment ? theme.textSecondary : .white,
        scale: theme.textScale
      )
    }
    interaction.endGroup()
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

/// The input-language cheat sheet. Every device compiles into these moves;
/// the status bar shows the mouse doing it live.
private struct KeyLegend: Block {
  let theme: Theme

  var body: some Block {
    VStack(spacing: 4, alignment: .leading) {
      Text("j/f  down/up").legendStyle(theme)
      Text("k/d  right/left").legendStyle(theme)
      Text("l/s  in/out").legendStyle(theme)
      Text("enter  activate").legendStyle(theme)
      Text("esc  end edit").legendStyle(theme)
      Text("mouse  = macro").legendStyle(theme)
    }
  }
}

extension Text {
  fileprivate func legendStyle(_ theme: Theme) -> Text {
    fontScale(theme.textScale).foregroundColor(theme.textSecondary)
  }
}

private struct DemoButton: Block {
  let label: String
  let theme: Theme
  let accent: Color
  let action: () -> Void

  var body: some Block {
    Interactive(id: "button:\(label)", action: action) { phase in
      Text(label)
        .fontScale(theme.textScale)
        .foregroundColor(.white)
        .padding(EdgeInsets(leading: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: theme.itemHeight, alignment: .leading)
        .background(theme.buttonColor(for: phase, accent: accent))
        .border(phase == .idle ? theme.border : accent, width: 1)
    }
  }
}

private struct CheckRow: Block {
  let label: String
  let isOn: Bool
  let theme: Theme
  let accent: Color
  let action: () -> Void

  var body: some Block {
    Interactive(id: "check:\(label)", action: action) { phase in
      HStack(spacing: 10, alignment: .center) {
        ZStack {
          isOn ? accent : theme.buttonIdle
          if isOn {
            Text("+")
              .fontScale(theme.textScale)
              .foregroundColor(.white)
          }
        }
        .frame(width: 20, height: 20)
        .border(isOn ? accent : theme.border, width: 1)

        Text(label)
          .fontScale(theme.textScale)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: theme.itemHeight, alignment: .leading)
      .padding(EdgeInsets(leading: 6))
      .background(theme.highlightColor(for: phase))
    }
  }
}

private struct SwatchGrid: Block {
  let theme: Theme
  let state: DemoState

  var body: some Block {
    VStack(spacing: 8, alignment: .leading) {
      HStack(spacing: 6) {
        Swatch(label: "Blue", color: theme.blue, theme: theme, selected: state.accentName == "Blue") {
          state.accent = theme.blue
          state.accentName = "Blue"
        }
        Swatch(label: "Green", color: theme.green, theme: theme, selected: state.accentName == "Green") {
          state.accent = theme.green
          state.accentName = "Green"
        }
        Swatch(label: "Red", color: theme.red, theme: theme, selected: state.accentName == "Red") {
          state.accent = theme.red
          state.accentName = "Red"
        }
      }
      HStack(spacing: 6) {
        Swatch(label: "Yellow", color: theme.yellow, theme: theme, selected: state.accentName == "Yellow") {
          state.accent = theme.yellow
          state.accentName = "Yellow"
        }
        Swatch(label: "Orange", color: theme.orange, theme: theme, selected: state.accentName == "Orange") {
          state.accent = theme.orange
          state.accentName = "Orange"
        }
        Swatch(label: "Purple", color: theme.purple, theme: theme, selected: state.accentName == "Purple") {
          state.accent = theme.purple
          state.accentName = "Purple"
        }
      }
    }
  }
}

private struct Swatch: Block {
  let label: String
  let color: Color
  let theme: Theme
  let selected: Bool
  let action: () -> Void

  var body: some Block {
    Interactive(id: "swatch:\(label)", action: action) { phase in
      VStack(spacing: 4, alignment: .leading) {
        color
          .frame(width: 26, height: 26)
          .border(selected ? Color.white : theme.border, width: selected ? 2 : 1)
        Text(label)
          .fontScale(theme.textScale)
          .foregroundColor(selected ? .white : theme.textSecondary)
      }
      .padding(2)
      .background(theme.highlightColor(for: phase))
    }
  }
}

private struct AsciiPanel: PrimitiveBlock {
  let theme: Theme
  let state: DemoState

  var expandsHorizontally: Bool { true }
  var expandsVertically: Bool { true }

  func sizeThatFits(_ proposal: Size) -> Size { proposal }

  func draw(into drawList: inout DrawList, in rect: Rect) {
    let printableRows: [[UInt8]] = stride(from: 0x20, through: 0x70, by: 0x10).map { first in
      let last = min(first + 0x0f, 0x7e)
      return Array(String(format: "%02X  ", first).utf8) + (first...last).map(UInt8.init)
    }
    let lines = [Array("20x28 PRINTABLE  ASCII  20..7E".utf8)] + printableRows

    // Fit the specimen to the assigned rect with an integer text scale.
    let metrics = FontMetrics()
    let availableWidth = rect.size.width - 2 * theme.panelPadding
    let availableHeight = rect.size.height - 2 * theme.panelPadding
    let longestLine = Float(lines.map(\.count).max() ?? 1)
    let widthScale = availableWidth / (longestLine * metrics.cellAdvance)
    let heightScale = availableHeight / (Float(lines.count) * metrics.lineAdvance)
    let scale = max(1, min(3, floor(min(widthScale, heightScale))))
    let origin = Point(x: rect.minX + theme.panelPadding, y: rect.minY + theme.panelPadding)

    if state.grid {
      let gridColor = Color(r: 0.5, g: 0.6, b: 0.8, a: 0.06)
      var x =
        rect.minX
        + (metrics.cellAdvance * scale - rect.minX.truncatingRemainder(dividingBy: metrics.cellAdvance * scale))
      while x < rect.maxX {
        drawList.fillRect(Rect(x: x.rounded(), y: rect.minY, width: 1, height: rect.size.height), color: gridColor)
        x += metrics.cellAdvance * scale
      }
      var y =
        rect.minY
        + (metrics.lineAdvance * scale - rect.minY.truncatingRemainder(dividingBy: metrics.lineAdvance * scale))
      while y < rect.maxY {
        drawList.fillRect(Rect(x: rect.minX, y: y.rounded(), width: rect.size.width, height: 1), color: gridColor)
        y += metrics.lineAdvance * scale
      }
    }

    if state.axis {
      let axisColor = Color(r: state.accent.r, g: state.accent.g, b: state.accent.b, a: 0.55)
      let midX = (rect.minX + rect.size.width / 2).rounded()
      let midY = (rect.minY + rect.size.height / 2).rounded()
      drawList.fillRect(Rect(x: rect.minX, y: midY, width: rect.size.width, height: 1), color: axisColor)
      drawList.fillRect(Rect(x: midX, y: rect.minY, width: 1, height: rect.size.height), color: axisColor)
    }

    for (row, bytes) in lines.enumerated() {
      drawList.text(
        String(decoding: bytes, as: UTF8.self),
        at: Point(
          x: origin.x,
          y: origin.y + Float(row) * metrics.lineAdvance * scale
        ),
        color: row == 0 ? theme.yellow : .white,
        scale: scale
      )
    }

    if state.wireframe {
      let boxColor = Color(r: 1, g: 1, b: 1, a: 0.22)
      for (row, bytes) in lines.enumerated() {
        for column in 0..<bytes.count {
          drawList.strokeRect(
            Rect(
              x: origin.x + Float(column) * metrics.cellAdvance * scale,
              y: origin.y + Float(row) * metrics.lineAdvance * scale,
              width: metrics.glyphWidth * scale,
              height: metrics.glyphHeight * scale
            ),
            width: 1,
            color: boxColor
          )
        }
      }
    }
  }
}

private struct Theme {
  var margin: Float = 12
  var spacing: Float = 8
  var panelPadding: Float = 12
  var headerHeight: Float = 42
  var statusHeight: Float = 26
  var itemHeight: Float = 32
  var textScale: Float = 0.5

  var background = Color(r: 0.045, g: 0.055, b: 0.075, a: 1)
  var panelBackground = Color(r: 0.065, g: 0.075, b: 0.10, a: 1)
  var headerBackground = Color(r: 0.075, g: 0.09, b: 0.13, a: 1)
  var statusBackground = Color(r: 0.04, g: 0.11, b: 0.09, a: 1)
  var border = Color(r: 0.16, g: 0.19, b: 0.25, a: 1)
  var buttonIdle = Color(r: 0.09, g: 0.11, b: 0.15, a: 1)
  var buttonHover = Color(r: 0.12, g: 0.16, b: 0.23, a: 1)
  var buttonPressed = Color(r: 0.18, g: 0.28, b: 0.42, a: 1)
  var textSecondary = Color(r: 0.52, g: 0.56, b: 0.66, a: 1)
  var blue = Color(r: 0.20, g: 0.62, b: 0.98, a: 1)
  var green = Color(r: 0.3, g: 0.8, b: 0.4, a: 1)
  var red = Color(r: 0.9, g: 0.3, b: 0.3, a: 1)
  var yellow = Color(r: 1, g: 0.85, b: 0.25, a: 1)
  var orange = Color(r: 1, g: 0.55, b: 0.15, a: 1)
  var purple = Color(r: 0.7, g: 0.3, b: 0.9, a: 1)

  /// Button background for the current interaction phase; a press flashes
  /// the accent color.
  func buttonColor(for phase: InteractionPhase, accent: Color) -> Color {
    switch phase {
    case .idle: buttonIdle
    case .hovered: buttonHover
    case .pressed: accent
    }
  }

  /// Subtle row highlight behind hovered or pressed rows.
  func highlightColor(for phase: InteractionPhase) -> Color {
    switch phase {
    case .idle: .clear
    case .hovered: Color(r: 1, g: 1, b: 1, a: 0.06)
    case .pressed: Color(r: 1, g: 1, b: 1, a: 0.12)
    }
  }
}
