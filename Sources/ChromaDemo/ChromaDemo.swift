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

  var title: String { "Chroma Demo" }
  var windowSize: Size { Size(width: 960, height: 640) }
  var minimumRefreshRate: Double { 30 }

  var keyBindings: KeyBindings {
    KeyBindings {
      bind("c", modifiers: .command, to: .editing(.copy))
      bind("v", modifiers: .command, to: .editing(.paste))
      bind("a", modifiers: .command, to: .editing(.selectAll))
      bind(.backspace, to: .editing(.backspace))
      bind(.delete, to: .editing(.deleteForward))
      bind(.leftArrow, to: .editing(.moveCaretLeft))
      bind(.rightArrow, to: .editing(.moveCaretRight))
      bind(.home, to: .editing(.moveCaretToStart))
      bind(.end, to: .editing(.moveCaretToEnd))
      bind(.enter, to: .editing(.submit))
      bind(.escape, to: .editing(.endEditing))
      bind(.space, to: .action(.activate))
      bind(.pageUp, to: .navigation(.pageUp))
      bind(.pageDown, to: .navigation(.pageDown))
      bind("j", to: .navigation(.down))
      bind("f", to: .navigation(.up))
      bind("d", to: .navigation(.left))
      bind("k", to: .navigation(.right))
      bind("l", to: .navigation(.in))
      bind("s", to: .navigation(.out))
    }
  }

  var body: some Block {
    DemoView(state: state)
      .chromaTheme(.dark)
  }
}

private final class DemoState {
  enum Page: String, CaseIterable {
    case navigation = "Navigation"
    case textInput = "Text input"
    case textSelection = "Copy & paste"
    case scrolling = "Scrolling"
  }

  var page: Page = .navigation
  var name = ""
  var message = "Activate a control"
  var isModalPresented = false
  let scrollController = ScrollViewController()
}

private let smallTextScale: Float = 0.65
private let titleTextScale: Float = 0.9

private struct DemoView: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 0) {
        DemoHeader()
        ZStack {
          HStack(spacing: 0) {
            DemoSidebar(state: state)
              .sizing(x: .fixed(210))
              .sizing(y: .grow)
              .background(theme.surface)
            DemoPage(state: state)
              .sizing(x: .grow, y: .grow)
              .clipped()
              .background(theme.background)
          }
          .sizing(x: .grow, y: .grow)
          if state.isModalPresented {
            Color(r: 0, g: 0, b: 0, a: 0.65)
            VStack {
              Spacer()
              HStack {
                Spacer()
                DemoModal(state: state)
                  .sizing(x: .fixed(560))
                Spacer()
              }
              Spacer()
            }
            .sizing(x: .grow, y: .grow)
          }
        }
        .sizing(x: .grow, y: .grow)
        DemoFooter(state: state)
      }
      .background(theme.background)
    }
  }
}

private struct DemoHeader: Block {
  var body: some Block {
    ThemeReader { theme in
      HStack(spacing: 10) {
        Text("CHROMA").fontScale(titleTextScale).foregroundColor(theme.accent)
        Text("Demo").fontScale(smallTextScale).foregroundColor(theme.foreground)
        Spacer()
        Text("30 FPS minimum refresh")
          .fontScale(smallTextScale)
          .foregroundColor(theme.secondaryForeground)
        LowRateAnimation(color: theme.accent)
          .sizing(x: .fixed(110), y: .fixed(14))
        Text("j/f/d/k move  •  l/s change depth")
          .fontScale(smallTextScale)
          .foregroundColor(theme.secondaryForeground)
      }
      .padding(12)
      .background(theme.elevatedSurface)
      .border(theme.border)
    }
  }
}

private struct LowRateAnimation: PrimitiveBlock {
  let color: Color

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let dotSize: Float = 10
    let travel = max(0, rect.size.width - dotSize)
    let elapsed = Date().timeIntervalSinceReferenceDate
    let phase = Float(elapsed.truncatingRemainder(dividingBy: 4) / 4)
    let progress = phase < 0.5 ? phase * 2 : (1 - phase) * 2
    let track = Rect(
      x: rect.minX,
      y: rect.minY + rect.size.height / 2 - 1,
      width: rect.size.width,
      height: 2)
    let dot = Rect(
      x: rect.minX + travel * progress,
      y: rect.minY + (rect.size.height - dotSize) / 2,
      width: dotSize,
      height: dotSize)

    drawList.fillRoundedRect(track, radius: 1, color: Color(r: color.r, g: color.g, b: color.b, a: 0.25))
    drawList.fillRoundedRect(dot, radius: dotSize / 2, color: color)
  }
}

private struct DemoSidebar: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 8) {
        Text("EXAMPLES")
          .fontScale(smallTextScale)
          .foregroundColor(theme.secondaryForeground)
          .padding(4)
        Button("Navigation", id: WidgetID("sidebar.navigation"), fontScale: smallTextScale) {
          state.page = .navigation
        }
        .sizing(x: .grow)
        Button("Text input", id: WidgetID("sidebar.text"), fontScale: smallTextScale) {
          state.page = .textInput
        }
        .sizing(x: .grow)
        Button("Copy & paste", id: WidgetID("sidebar.copy"), fontScale: smallTextScale) {
          state.page = .textSelection
        }
        .sizing(x: .grow)
        Button("Scrolling", id: WidgetID("sidebar.scroll"), fontScale: smallTextScale) {
          state.page = .scrolling
        }
        .sizing(x: .grow)
        Spacer()
      }
      .padding(12)
    }
  }
}

private struct DemoPage: PrimitiveBlock {
  let state: DemoState

  private var content: any Block {
    switch state.page {
    case .navigation: NavigationExample(state: state)
    case .textInput: TextInputExample(state: state)
    case .textSelection: TextSelectionExample(state: state)
    case .scrolling: ScrollingExample(state: state)
    }
  }

  var expandsHorizontally: Bool { true }
  var expandsVertically: Bool { true }
  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }
  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

private struct PageHeading: Block {
  let title: String
  let detail: String

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 6) {
        Text(title).fontScale(titleTextScale).foregroundColor(theme.accent)
        Text(detail).fontScale(smallTextScale).foregroundColor(theme.secondaryForeground)
      }
    }
  }
}

private struct NavigationExample: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 18) {
        PageHeading(
          title: "Keyboard navigation",
          detail: "Move between the sidebar and this pane with d/k."
        )
        VStack(spacing: 10) {
          Button("First action", id: WidgetID("navigation.first"), fontScale: smallTextScale) {
            state.message = "First action"
          }
          HStack(spacing: 10) {
            Button("Left", id: WidgetID("navigation.left"), fontScale: smallTextScale) {
              state.message = "Left"
            }
            Button("Middle", id: WidgetID("navigation.middle"), fontScale: smallTextScale) {
              state.message = "Middle"
            }
            Button("Right", id: WidgetID("navigation.right"), fontScale: smallTextScale) {
              state.message = "Right"
            }
          }
          Button("Last action", id: WidgetID("navigation.last"), fontScale: smallTextScale) {
            state.message = "Last action"
          }
        }
        .padding(16)
        .roundedBackground(theme.surface, radius: 8)
        .roundedBorder(theme.border, radius: 8)
        Button("Show modal", id: WidgetID("navigation.modal"), fontScale: smallTextScale) {
          state.isModalPresented = true
        }
        Text("Last activation: \(state.message)")
          .fontScale(smallTextScale)
          .foregroundColor(theme.foreground)
      }
      .padding(24)
    }
  }
}

private struct TextInputExample: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 18) {
        PageHeading(
          title: "Text input",
          detail: "Activate the field, type normally, and press Escape to stop editing."
        )
        TextField(
          "Your name",
          id: WidgetID("text.name"),
          fontScale: smallTextScale,
          text: { state.name },
          onChange: { state.name = $0 },
          onSubmit: { state.message = "Submitted: \($0)" }
        )
        .sizing(x: .fixed(520))
        Text(state.name.isEmpty ? "No text entered" : "Hello, \(state.name)")
          .fontScale(smallTextScale)
          .foregroundColor(theme.foreground)
      }
      .padding(24)
    }
  }
}

private struct TextSelectionExample: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 18) {
        PageHeading(
          title: "Copy & paste",
          detail: "Drag to select, or press Command-A; use Command-C and Command-V to copy and paste."
        )
        VStack(spacing: 10) {
          Text("Select and copy any part of this sentence.")
            .selectable(WidgetID("copy.source"))
            .fontScale(smallTextScale)
            .foregroundColor(theme.foreground)
          Text("Selections use the system clipboard.")
            .selectable(WidgetID("copy.detail"))
            .fontScale(smallTextScale)
            .foregroundColor(theme.secondaryForeground)
        }
        .padding(16)
        .roundedBackground(theme.surface, radius: 8)
        .roundedBorder(theme.border, radius: 8)
        TextField(
          "Paste copied text here",
          id: WidgetID("copy.destination"),
          fontScale: smallTextScale,
          text: { state.name },
          onChange: { state.name = $0 }
        )
        .sizing(x: .fixed(520))
      }
      .padding(24)
    }
  }
}

private struct ScrollingExample: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 14) {
        PageHeading(
          title: "Scrolling",
          detail: "Use the wheel, Page Up/Down, Home/End, or the buttons below."
        )
        HStack(spacing: 8) {
          Button("Top", id: WidgetID("scroll.top"), fontScale: smallTextScale) {
            state.scrollController.scrollToTop()
          }
          Button("Bottom", id: WidgetID("scroll.bottom"), fontScale: smallTextScale) {
            state.scrollController.scrollToBottom()
          }
        }
        ScrollView(id: WidgetID("demo.scroll"), controller: state.scrollController) {
          VStack(spacing: 5) {
            for index in 1...50 {
              Text("Row \(index)")
                .fontScale(smallTextScale)
                .foregroundColor(index.isMultiple(of: 10) ? theme.accent : theme.foreground)
                .padding(7)
                .sizing(x: .grow)
                .roundedBackground(theme.surface, radius: 4)
            }
          }
          .padding(8)
        }
        .sizing(x: .grow, y: .grow)
        .roundedBorder(theme.border, radius: 8)
      }
      .padding(24)
    }
  }
}

private struct DemoModal: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 14) {
        Text("Modal overlay")
          .fontScale(titleTextScale)
          .foregroundColor(theme.accent)
        Text("ZStack layers it over the page.")
          .fontScale(smallTextScale)
          .foregroundColor(theme.foreground)
        Button("Dismiss", id: WidgetID("modal.dismiss"), fontScale: smallTextScale) {
          state.isModalPresented = false
        }
      }
      .padding(24)
      .roundedBackground(theme.elevatedSurface, radius: 8)
      .roundedBorder(theme.accent, radius: 8)
    }
  }
}

private struct DemoFooter: Block {
  let state: DemoState

  var body: some Block {
    ThemeReader { theme in
      HStack(spacing: 12) {
        Text("Movement: j/f/d/k  •  Enter edits  •  Editing: Escape returns to movement")
          .fontScale(smallTextScale)
          .foregroundColor(theme.secondaryForeground)
        Spacer()
        Text(state.page.rawValue)
          .fontScale(smallTextScale)
          .foregroundColor(theme.accent)
      }
      .padding(9)
      .background(theme.elevatedSurface)
      .border(theme.border)
    }
  }
}
