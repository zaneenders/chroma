import Chroma
import Foundation

#if METAL_BACKEND
import MetalBackend
typealias PlatformApp = MetalApp
#elseif WAYLAND_BACKEND
import WaylandBackend
typealias PlatformApp = WaylandApp
#else
#error("ChromaDemo requires a rendering backend.")
#endif

@main
struct ChromaDemo: PlatformApp {
  private let state = DemoState()

  var title: String { "Chroma Feature Tour" }
  var windowSize: Size { Size(width: 1100, height: 720) }

  var keyBindings: KeyBindings {
    .defaults.overlay {
      bind("j", to: .navigation(.down))
      bind("f", to: .navigation(.up))
      bind("d", to: .navigation(.left))
      bind("k", to: .navigation(.right))
      bind("l", to: .navigation(.in))
      bind("h", to: .navigation(.out))
      bind("t", to: .application("tour.toggle-theme"))
      bind("?", to: .application("tour.help"))
      bind("1", to: .application("tour.overview"))
      bind("2", to: .application("tour.layout"))
      bind("3", to: .application("tour.controls"))
      bind("4", to: .application("tour.text-input"))
      bind("5", to: .application("tour.navigation"))
      bind("6", to: .application("tour.scrolling"))
      bind("7", to: .application("tour.selection"))
      bind("8", to: .application("tour.files"))
      bind("s", to: .application("file-browser.parent"))
      bind("r", to: .application("file-browser.refresh"))
      bind(.enter, modifiers: [.command], to: .action(.submit))
    }
  }

  var body: some Block {
    DynamicTheme(state: state, content: commandHandlers(DemoShell(state: state)))
  }

  @MainActor
  private func commandHandlers(_ content: some Block) -> some Block {
    content
      .onCommand(.application("tour.toggle-theme")) {
        state.useLightTheme.toggle()
        state.log("Theme changed to \(state.useLightTheme ? "light" : "dark")")
        return .handled
      }
      .onCommand(.application("tour.help")) {
        state.showHelp.toggle()
        state.log(state.showHelp ? "Keyboard help opened" : "Keyboard help closed")
        return .handled
      }
      .onCommand(.application("tour.overview")) { state.select(.overview); return .handled }
      .onCommand(.application("tour.layout")) { state.select(.layout); return .handled }
      .onCommand(.application("tour.controls")) { state.select(.controls); return .handled }
      .onCommand(.application("tour.text-input")) { state.select(.textInput); return .handled }
      .onCommand(.application("tour.navigation")) { state.select(.navigation); return .handled }
      .onCommand(.application("tour.scrolling")) { state.select(.scrolling); return .handled }
      .onCommand(.application("tour.selection")) { state.select(.selection); return .handled }
      .onCommand(.application("tour.files")) { state.select(.files); return .handled }
      .onCommand(.application("file-browser.parent")) {
        guard state.page == .files else { return .ignored }
        state.browser.goOut()
        state.log("Moved to the parent directory")
        return .handled
      }
      .onCommand(.application("file-browser.refresh")) {
        guard state.page == .files else { return .ignored }
        state.browser.reload()
        state.log("Refreshed the file browser")
        return .handled
      }
  }
}

private final class DemoState {
  enum Page: String, CaseIterable {
    case overview = "Overview"
    case layout = "Layout & Styling"
    case controls = "Controls & Commands"
    case textInput = "Text Input"
    case navigation = "Navigation"
    case scrolling = "Scrolling"
    case selection = "Text Selection"
    case files = "File Browser"

    var number: Int { Self.allCases.firstIndex(of: self)! + 1 }
  }

  var page: Page = .overview
  var useLightTheme = false
  var showHelp = false
  var layoutSpacing: Float = 10
  var reversedNavigation = false
  var name = ""
  var email = ""
  var events = ["Welcome to the Chroma feature tour"]
  let longListController = ScrollViewController()
  let browser = FileBrowserState()

  func select(_ page: Page) {
    self.page = page
    showHelp = false
    log("Opened \(page.rawValue)")
  }

  func log(_ message: String) {
    events.insert(message, at: 0)
    if events.count > 5 { events.removeLast() }
  }
}

private struct DynamicTheme<Content: Block>: PrimitiveBlock {
  let state: DemoState
  let content: Content

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let themed = context
      .withTheme(state.useLightTheme ? .light : .dark)
      .withTextScale(0.62)
    return BlockEngine.measure(content, proposal: proposal, context: themed)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let themed = context
      .withTheme(state.useLightTheme ? .light : .dark)
      .withTextScale(0.62)
    BlockEngine.draw(content, into: &drawList, in: rect, context: themed)
  }
}

private struct DemoShell: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 0, alignment: .leading) {
        Header(state: state)
          HStack(spacing: 0, alignment: .top) {
          Sidebar(state: state)
            .frame(width: 205, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(theme.surface)
          DynamicPage(state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .background(theme.background)
        }
        Footer(state: state)
      }
      .background(theme.background)
    }
  }
}

private struct Header: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      HStack(spacing: 12, alignment: .center) {
        Text("CHROMA").fontScale(1.25).foregroundColor(theme.accent)
        Text("Feature Tour").foregroundColor(theme.foreground)
        Spacer()
        Button("Theme (t)", id: WidgetID("header.theme")) {
          state.useLightTheme.toggle()
          state.log("Theme changed")
        }
        Button("Help (?)", id: WidgetID("header.help")) {
          state.showHelp.toggle()
        }
      }
      .padding(12)
      .background(theme.elevatedSurface)
      .border(theme.border)
    }
  }
}

private struct Sidebar: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 7, alignment: .leading) {
        Text("FEATURES").foregroundColor(theme.secondaryForeground).padding(8)
        for page in DemoState.Page.allCases {
          Button("\(page.number)  \(page.rawValue)", id: WidgetID("sidebar.\(page.number)")) {
            state.select(page)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        Spacer()
        Text("Application keymap")
          .foregroundColor(theme.accent)
        Text("j/f/d/k  move")
          .foregroundColor(theme.secondaryForeground)
        Text("l/h      in/out")
          .foregroundColor(theme.secondaryForeground)
        Text("1–8      jump pages")
          .foregroundColor(theme.secondaryForeground)
      }
      .padding(12)
    }
  }
}

private struct Footer: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      HStack(spacing: 20, alignment: .center) {
        Text("Arrows move  •  Tab/Shift-Tab cycle  •  Enter activate  •  Esc cancel")
          .foregroundColor(theme.secondaryForeground)
        Spacer()
        Text(state.page.rawValue).foregroundColor(theme.accent)
      }
      .padding(10)
      .background(theme.elevatedSurface)
      .border(theme.border)
    }
  }
}

private struct DynamicPage: PrimitiveBlock {
  let state: DemoState

  private func page() -> any Block {
    if state.showHelp { return HelpPage() }
    switch state.page {
    case .overview: return OverviewPage(state: state)
    case .layout: return LayoutPage(state: state)
    case .controls: return ControlsPage(state: state)
    case .textInput: return TextInputPage(state: state)
    case .navigation: return NavigationPage(state: state)
    case .scrolling: return ScrollingPage(state: state)
    case .selection: return SelectionPage()
    case .files: return FileBrowserPage(state: state.browser)
    }
  }

  var expandsHorizontally: Bool { true }
  var expandsVertically: Bool { true }
  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }
  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(page(), into: &drawList, in: rect, context: context)
  }
}

private struct PageTitle: Block {
  let title: String
  let subtitle: String
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 6, alignment: .leading) {
        Text(title).fontScale(1.7).foregroundColor(theme.accent)
        Text(subtitle).foregroundColor(theme.secondaryForeground)
      }
    }
  }
}

private struct FeatureCard<Content: Block>: Block {
  let title: String
  let content: Content
  init(_ title: String, @BlockBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 10, alignment: .leading) {
        Text(title).fontScale(1.15).foregroundColor(theme.foreground)
        content
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .roundedBackground(theme.surface, radius: 10)
      .roundedBorder(theme.border, radius: 10)
    }
  }
}

private struct OverviewPage: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 14, alignment: .leading) {
        PageTitle(title: "Build native interfaces in Swift", subtitle: "This tour is itself a Chroma application. Every control below is live.")
        HStack(spacing: 12, alignment: .top) {
          FeatureCard("Keyboard first") {
            Text("Axis-aware focus trees and semantic commands.")
              .foregroundColor(theme.secondaryForeground)
            Button("Open Navigation", id: WidgetID("overview.navigation")) { state.select(.navigation) }
          }
          FeatureCard("Composable rendering") {
            Text("Stacks, themes, clipping, and painter ordering.")
              .foregroundColor(theme.secondaryForeground)
            Button("Open Layout", id: WidgetID("overview.layout")) { state.select(.layout) }
          }
        }
        HStack(spacing: 12, alignment: .top) {
          FeatureCard("Real interaction") {
            Text("Buttons, fields, selection, and semantic roles.")
              .foregroundColor(theme.secondaryForeground)
            Button("Try Controls", id: WidgetID("overview.controls")) { state.select(.controls) }
          }
          FeatureCard("Complete example") {
            Text("Dynamic files, stable focus, and scroll-to-visible.")
              .foregroundColor(theme.secondaryForeground)
            Button("Browse Files", id: WidgetID("overview.files")) { state.select(.files) }
          }
        }
        FeatureCard("Try command jumping") {
          Text("Press 1–8 from navigation mode. The physical key resolves to an application command; the nearest handler changes pages.")
            .foregroundColor(theme.secondaryForeground)
        }
      }.padding(20)
    }
  }
}

private struct LayoutPage: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 14, alignment: .leading) {
        PageTitle(title: "Layout & Styling", subtitle: "Stacks negotiate size; modifiers paint in source order.")
        FeatureCard("Live spacing: \(Int(state.layoutSpacing))") {
          HStack(spacing: 8) {
            Button("−", id: WidgetID("layout.less")) { state.layoutSpacing = max(0, state.layoutSpacing - 4) }
            Button("+", id: WidgetID("layout.more")) { state.layoutSpacing += 4 }
          }
          DynamicSpacingExample(state: state)
        }
        HStack(spacing: 12, alignment: .top) {
          FeatureCard("Modifier composition") {
            Text("padding → background → rounded border")
              .foregroundColor(theme.secondaryForeground)
              .padding(12)
              .roundedBackground(theme.elevatedSurface, radius: 12)
              .roundedBorder(theme.accent, radius: 12, width: 2)
          }
          FeatureCard("Theme tokens") {
            Text("Accent").foregroundColor(theme.accent)
            Text("Positive").foregroundColor(theme.positive)
            Text("Warning").foregroundColor(theme.warning)
            Text("Negative").foregroundColor(theme.negative)
          }
        }
      }.padding(20)
    }
  }
}

private struct DynamicSpacingExample: PrimitiveBlock {
  let state: DemoState
  var expandsHorizontally: Bool { true }
  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { Size(width: proposal.width, height: 70) }
  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let example = HStack(spacing: state.layoutSpacing) {
      Color(r: 0.2, g: 0.62, b: 0.98, a: 1).frame(width: 70, height: 50)
      Color(r: 0.3, g: 0.8, b: 0.4, a: 1).frame(width: 70, height: 50)
      Color(r: 1, g: 0.65, b: 0.2, a: 1).frame(width: 70, height: 50)
      Spacer()
    }
    BlockEngine.draw(example, into: &drawList, in: rect, context: context)
  }
}

private struct ControlsPage: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      HStack(spacing: 14, alignment: .top) {
        VStack(spacing: 14, alignment: .leading) {
          PageTitle(title: "Controls & Commands", subtitle: "Buttons describe roles; commands describe intent; handlers own behavior.")
          FeatureCard("Semantic action roles") {
            Text("Command-Enter invokes the default action. Escape targets cancel.")
              .foregroundColor(theme.secondaryForeground)
            HStack(spacing: 8) {
              Button("Save", id: WidgetID("controls.save"), role: .defaultAction) { state.log("Default Save action invoked") }
              Button("Delete", id: WidgetID("controls.delete"), role: .destructive) { state.log("Destructive Delete action invoked") }
              Button("Cancel", id: WidgetID("controls.cancel"), role: .cancel) { state.log("Cancel action invoked") }
            }
          }
          FeatureCard("Semantic routing") {
            Text("The demo's t key sends tour.toggle-theme. No widget knows which physical key produced it.")
              .foregroundColor(theme.secondaryForeground)
            Button("Toggle theme", id: WidgetID("controls.theme")) { state.useLightTheme.toggle(); state.log("Theme toggled by button") }
          }
        }
        EventLog(state: state)
          .frame(width: 300, alignment: .topLeading)
          .frame(maxHeight: .infinity, alignment: .topLeading)
      }.padding(20)
    }
  }
}

private struct EventLog: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      FeatureCard("Event log") {
        for event in state.events {
          Text("• \(event)").foregroundColor(theme.secondaryForeground)
        }
      }
    }
  }
}

private struct TextInputPage: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 14, alignment: .leading) {
        PageTitle(title: "Text Input", subtitle: "Activate a field to enter editing mode; Escape returns to navigation.")
        FeatureCard("Editing versus navigation") {
          Text("Outside a field, navigation aliases move focus. Inside a field, printable keys insert text.")
            .foregroundColor(theme.secondaryForeground)
          TextField("Name", id: WidgetID("input.name"), text: { state.name }, onChange: { state.name = $0 }) { value in
            state.log("Submitted name: \(value)")
          }
          TextField("Email", id: WidgetID("input.email"), text: { state.email }, onChange: { state.email = $0 }) { value in
            state.log("Submitted email: \(value)")
          }
          Text("Caret: arrows/home/end • edit: backspace/delete • Enter: submit")
            .foregroundColor(theme.secondaryForeground)
        }
        FeatureCard("Live model") {
          Text("name = \(state.name.isEmpty ? "<empty>" : state.name)").foregroundColor(theme.accent)
          Text("email = \(state.email.isEmpty ? "<empty>" : state.email)").foregroundColor(theme.accent)
        }
      }.padding(20)
    }
  }
}

private struct NavigationPage: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 14, alignment: .leading) {
        PageTitle(title: "Focus-tree Navigation", subtitle: "Movement follows declared axes and bubbles through nested groups.")
        FeatureCard("Nested vertical and horizontal groups") {
          Text("Move down to the row, press l/Enter to enter it, then use d/k or Left/Right.")
            .foregroundColor(theme.secondaryForeground)
          DynamicNavigationExample(state: state)
          Button("Reorder stable IDs", id: WidgetID("navigation.reorder")) {
            state.reversedNavigation.toggle()
            state.log("Navigation controls reordered; focus follows WidgetID")
          }
        }
        FeatureCard("Vocabulary") {
          Text("Directions: up/down/left/right • depth: in/out • linear: Tab/Shift-Tab • action: Enter")
            .foregroundColor(theme.secondaryForeground)
        }
      }.padding(20)
    }
  }
}

private struct DynamicNavigationExample: PrimitiveBlock {
  let state: DemoState
  var expandsHorizontally: Bool { true }
  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { Size(width: proposal.width, height: 135) }
  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let names = state.reversedNavigation ? ["Delta", "Charlie", "Bravo"] : ["Bravo", "Charlie", "Delta"]
    let example = VStack(spacing: 8, alignment: .leading) {
      Button("Alpha", id: WidgetID("navigation.alpha")) { state.log("Activated Alpha") }
      HStack(spacing: 8) {
        for name in names {
          Button(name, id: WidgetID("navigation.\(name.lowercased())")) { state.log("Activated \(name)") }
        }
      }
      Button("Echo", id: WidgetID("navigation.echo")) { state.log("Activated Echo") }
    }
    BlockEngine.draw(example, into: &drawList, in: rect, context: context)
  }
}

private struct ScrollingPage: Block {
  let state: DemoState
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 12, alignment: .leading) {
        PageTitle(title: "Scrolling", subtitle: "Wheel, page, home/end, controllers, clipping, and persistent offsets.")
        HStack(spacing: 8) {
          Button("Top", id: WidgetID("scroll.top")) { state.longListController.scrollToTop() }
          Button("Middle", id: WidgetID("scroll.middle")) { state.longListController.scroll(to: 700) }
          Button("Bottom", id: WidgetID("scroll.bottom")) { state.longListController.scrollToBottom() }
        }
        ScrollView(id: WidgetID("tour.long-list"), controller: state.longListController) {
          VStack(spacing: 5, alignment: .leading) {
            for index in 1...80 {
              Text("Row \(index) — clipped interactive content keeps an independent scroll offset")
                .foregroundColor(index.isMultiple(of: 10) ? theme.accent : theme.foreground)
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .roundedBackground(index.isMultiple(of: 2) ? theme.surface : theme.elevatedSurface, radius: 5)
            }
          }.padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .roundedBorder(theme.border, radius: 8)
      }.padding(20)
    }
  }
}

private struct SelectionPage: Block {
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 14, alignment: .leading) {
        PageTitle(title: "Text Selection", subtitle: "Drag across text and press Command-C to copy the selected grapheme range.")
        FeatureCard("Selectable text") {
          Text("Chroma tracks selection by semantic text layout, including Unicode: café 👩🏽‍💻 🚀")
            .foregroundColor(theme.foreground)
            .fontScale(1.25)
            .selectable(WidgetID("selection.sample"))
          Text("Selection painting is clipped and emitted in painter order.")
            .foregroundColor(theme.secondaryForeground)
            .selectable(WidgetID("selection.second"))
        }
        FeatureCard("What this demonstrates") {
          Text("• drag hit-testing").foregroundColor(theme.secondaryForeground)
          Text("• grapheme-safe offsets").foregroundColor(theme.secondaryForeground)
          Text("• selection colors from the theme").foregroundColor(theme.secondaryForeground)
          Text("• backend clipboard integration").foregroundColor(theme.secondaryForeground)
        }
      }.padding(20)
    }
  }
}

private struct HelpPage: Block {
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 14, alignment: .leading) {
        PageTitle(title: "Keyboard Help", subtitle: "Bindings resolve to semantic commands before widgets handle them.")
        FeatureCard("Framework defaults") {
          Text("Arrow keys       directional movement").foregroundColor(theme.secondaryForeground)
          Text("Tab / Shift-Tab  next / previous leaf").foregroundColor(theme.secondaryForeground)
          Text("Enter / Space    activate").foregroundColor(theme.secondaryForeground)
          Text("Escape           cancel").foregroundColor(theme.secondaryForeground)
          Text("Page Up/Down     viewport movement").foregroundColor(theme.secondaryForeground)
          Text("Home / End       first / last").foregroundColor(theme.secondaryForeground)
        }
        FeatureCard("Demo overlay") {
          Text("j/f/d/k          down / up / left / right").foregroundColor(theme.secondaryForeground)
          Text("l/h              in / out").foregroundColor(theme.secondaryForeground)
          Text("1–8              jump directly to a feature page").foregroundColor(theme.secondaryForeground)
          Text("t                toggle theme").foregroundColor(theme.secondaryForeground)
          Text("s / r            file-browser parent / refresh").foregroundColor(theme.secondaryForeground)
          Text("?                close this help").foregroundColor(theme.secondaryForeground)
        }
      }.padding(20)
    }
  }
}

private final class FileBrowserState {
  struct Entry {
    let name: String
    let url: URL
    let isDirectory: Bool
  }

  private(set) var directory: URL
  private(set) var entries: [Entry] = []
  private(set) var message = ""
  let filesScrollController = ScrollViewController()
  private var lastRevealedEntry: WidgetID?

  init() {
    directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
    reload()
  }

  func open(_ entry: Entry) {
    guard entry.isDirectory else { message = entry.name; return }
    directory = entry.url.standardizedFileURL
    reload()
  }

  func goOut() {
    let parent = directory.deletingLastPathComponent().standardizedFileURL
    guard parent.path != directory.path else { message = "Already at filesystem root"; return }
    directory = parent
    reload()
  }

  func revealIfNeeded(id: WidgetID, rect: Rect, selected: Bool) {
    guard selected, lastRevealedEntry != id else { return }
    lastRevealedEntry = id
    filesScrollController.scrollToVisible(rect)
  }

  func reload() {
    lastRevealedEntry = nil
    filesScrollController.scrollToTop()
    do {
      let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
      entries = try urls.map { url in
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return Entry(name: url.lastPathComponent, url: url, isDirectory: values.isDirectory == true)
      }.sorted {
        if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      message = "\(entries.count) items"
    } catch {
      entries = []
      message = error.localizedDescription
    }
  }
}

private struct FileBrowserPage: Block {
  let state: FileBrowserState
  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 0, alignment: .leading) {
        VStack(spacing: 6, alignment: .leading) {
          PageTitle(title: "File Browser", subtitle: "A complete app: dynamic data, stable focus IDs, scrolling, and application commands.")
          Text(state.directory.path).foregroundColor(theme.foreground)
          Text("Enter/l open • s parent • r refresh").foregroundColor(theme.secondaryForeground)
        }.padding(16)
        ScrollView(id: WidgetID("files"), controller: state.filesScrollController) {
          VStack(spacing: 4, alignment: .leading) {
            for entry in state.entries { FileEntryButton(entry: entry, state: state) }
          }.padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Text(state.message).foregroundColor(theme.secondaryForeground).padding(10)
      }.padding(10)
    }
  }
}

private struct FileEntryButton: PrimitiveBlock {
  let entry: FileBrowserState.Entry
  let state: FileBrowserState
  private var id: WidgetID { WidgetID(entry.url.path) }
  private var label: String { entry.isDirectory ? "[DIR]  \(entry.name)/" : "       \(entry.name)" }
  private let padding = EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Button(label, id: id, padding: padding) {}.sizeThatFits(proposal, context: context)
  }
  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let style = context.theme.button
    let buttonState = context.buttonState(id: id, in: rect)
    state.revealIfNeeded(id: id, rect: rect, selected: buttonState.hovered)
    if buttonState.clicked { state.open(entry) }
    let background = buttonState.phase == .pressed ? style.pressedBackground : buttonState.phase == .hovered ? style.hoveredBackground : style.idleBackground
    drawList.fillRoundedRect(rect, radius: style.cornerRadius, color: background)
    drawList.strokeRoundedRect(rect, radius: style.cornerRadius, width: style.borderWidth, color: style.border)
    drawList.text(label, at: Point(x: rect.minX + padding.leading, y: rect.minY + padding.top), color: style.foreground)
  }
}
