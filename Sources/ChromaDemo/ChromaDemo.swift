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
  private let browser = FileBrowserState()

  var title: String { "Chroma Files" }
  var windowSize: Size { Size(width: 900, height: 650) }

  var body: some Block {
    FileBrowser(state: browser)
      .chromaTheme(.dark)
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
    directory =
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .standardizedFileURL
    reload()
  }

  func open(_ entry: Entry) {
    guard entry.isDirectory else {
      message = entry.name
      return
    }
    directory = entry.url.standardizedFileURL
    reload()
  }

  func goOut() {
    let parent = directory.deletingLastPathComponent().standardizedFileURL
    guard parent.path != directory.path else {
      message = "Already at filesystem root"
      return
    }
    directory = parent
    reload()
  }

  func revealIfNeeded(id: WidgetID, rect: Rect, selected: Bool) {
    guard selected, lastRevealedEntry != id else { return }
    lastRevealedEntry = id
    filesScrollController.scrollToVisible(rect)
  }

  private func reload() {
    lastRevealedEntry = nil
    filesScrollController.scrollToTop()
    do {
      let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
      )
      entries = try urls.map { url in
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return Entry(
          name: url.lastPathComponent,
          url: url,
          isDirectory: values.isDirectory == true
        )
      }
      .sorted {
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

private struct FileBrowser: Block {
  let state: FileBrowserState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 0, alignment: .leading) {
        CommandAction(command: .out) {
          state.goOut()
        }

        VStack(spacing: 8, alignment: .leading) {
          Text("FILES")
            .fontScale(2)
            .foregroundColor(theme.accent)
          Text(state.directory.path)
            .foregroundColor(theme.foreground)
          Text("j down   f up   k right   d left   l/enter open   s back")
            .foregroundColor(theme.secondaryForeground)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .roundedBackground(theme.elevatedSurface, radius: 12)
        .roundedBorder(theme.border, radius: 12)
        .padding(12)

        ScrollView(id: WidgetID("files"), controller: state.filesScrollController) {
          VStack(spacing: 4, alignment: .leading) {
            for entry in state.entries {
              FileEntryButton(entry: entry, state: state)
            }
          }
          .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        Text(state.message)
          .foregroundColor(theme.secondaryForeground)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(theme.elevatedSurface)
      }
      .background(theme.background)
    }
  }
}

private struct FileEntryButton: PrimitiveBlock {
  let entry: FileBrowserState.Entry
  let state: FileBrowserState

  private var id: WidgetID { WidgetID(entry.url.path) }
  private var label: String {
    entry.isDirectory ? "[DIR]  \(entry.name)/" : "       \(entry.name)"
  }
  private let padding = EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Button(label, id: id, padding: padding) {}.sizeThatFits(proposal, context: context)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let style = context.theme.button
    let buttonState = context.buttonState(id: id, in: rect)
    state.revealIfNeeded(id: id, rect: rect, selected: buttonState.hovered)
    if buttonState.clicked { state.open(entry) }

    let background: Color
    switch buttonState.phase {
    case .idle: background = style.idleBackground
    case .hovered: background = style.hoveredBackground
    case .pressed: background = style.pressedBackground
    }
    drawList.fillRoundedRect(rect, radius: style.cornerRadius, color: background)
    drawList.strokeRoundedRect(
      rect, radius: style.cornerRadius, width: style.borderWidth, color: style.border)
    drawList.text(
      label,
      at: Point(x: rect.minX + padding.leading, y: rect.minY + padding.top),
      color: style.foreground)
  }
}

private struct CommandAction: PrimitiveBlock {
  let command: UICommand
  let action: () -> Void

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { .zero }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    if context.input.commands.contains(command) {
      action()
    }
  }
}
