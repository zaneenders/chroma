import Chroma
import Foundation

struct Entry: Block {
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

struct Header: Block {
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

struct StatusBar: Block {
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

struct Sidebar: Block {
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

struct MainPanel: Block {
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
