import Chroma
import Foundation

struct Entry: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 0) {
        Header(theme: theme, state: state)
        HStack(spacing: DemoMetrics.margin) {
          Sidebar(theme: theme, state: state)
            .frame(width: 248, alignment: .topLeading)
          MainPanel(theme: theme, state: state)
        }
        .padding(DemoMetrics.margin)
        StatusBar(theme: theme, state: state)
      }
      .background(theme.background)
    }
  }
}

struct Header: Block {
  let theme: ChromaTheme
  let state: DemoState

  var body: some Block {
    VStack(spacing: 0) {
      Text(
        state.name.isEmpty
          ? "CHROMA  /  WORKBENCH"
          : "CHROMA  /  HELLO \(state.name.uppercased())"
      )
      .fontScale(DemoMetrics.textScale)
      .foregroundColor(state.accent)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(EdgeInsets(leading: DemoMetrics.margin))
      state.accent
        .frame(height: 1)
    }
    .frame(height: DemoMetrics.headerHeight)
    .background(theme.elevatedSurface)
  }
}

struct StatusBar: Block {
  let theme: ChromaTheme
  let state: DemoState

  var body: some Block {
    VStack(spacing: 0) {
      state.accent
        .frame(height: 1)
      HStack(spacing: 0) {
        if state.stats {
          Text("CHROMA")
            .fontScale(DemoMetrics.textScale)
            .foregroundColor(theme.positive)
        }
        Spacer()
        Text("Last action: \(state.lastAction) (\(state.actionCount))")
          .fontScale(DemoMetrics.textScale)
          .foregroundColor(theme.secondaryForeground)
      }
      .padding(EdgeInsets(leading: DemoMetrics.margin, trailing: DemoMetrics.margin))
    }
    .frame(height: DemoMetrics.statusHeight)
    .background(theme.surface)
  }
}

struct Sidebar: Block {
  let theme: ChromaTheme
  let state: DemoState

  var body: some Block {
    VStack(spacing: DemoMetrics.spacing, alignment: .leading) {
      SectionTitle(title: "CONTROLS", theme: theme)
      DemoButton(label: "New Project") {
        state.record("New Project")
      }
      DemoButton(label: "Open...") {
        state.record("Open...")
      }
      DemoButton(label: "Save") {
        state.record("Save")
      }

      Spacer().frame(height: DemoMetrics.spacing)
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

      Spacer().frame(height: DemoMetrics.spacing)
      SectionTitle(title: "PROFILE", theme: theme)
      TextField(
        "your name",
        id: WidgetID("field:name"),
        fontScale: DemoMetrics.textScale,
        padding: 7,
        style: theme.textField,
        text: { state.name },
        onChange: { state.name = $0 }
      )

      Spacer().frame(height: DemoMetrics.spacing)
      SectionTitle(title: "COLORS", theme: theme)
      SwatchGrid(theme: theme, state: state)

      Spacer().frame(height: DemoMetrics.spacing)
      SectionTitle(title: "KEYS", theme: theme)
      KeyLegend(theme: theme)
    }
    .padding(DemoMetrics.panelPadding)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(theme.surface)
    .border(theme.border, width: 1)
  }
}

struct MainPanel: Block {
  let theme: ChromaTheme
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
      .frame(height: DemoMetrics.itemHeight)
      .background(theme.elevatedSurface)

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
    .background(theme.surface)
    .border(theme.border, width: 1)
  }
}
