import Chroma
import Foundation

struct PackagePanel: Block {
  let theme: ChromaTheme
  let source: String
  let scrollController: ScrollViewController

  var body: some Block {
    ScrollView(
      id: WidgetID("demo:package-scroll"),
      showsIndicator: true,
      controller: scrollController
    ) {
      VStack(spacing: DemoMetrics.spacing, alignment: .leading) {
        Text("PACKAGE.SWIFT   /   UP-DOWN SELECT   /   WHEEL SCROLL")
          .fontScale(DemoMetrics.textScale)
          .foregroundColor(theme.warning)
        PackageSourceListing(
          theme: theme,
          source: source,
          scrollController: scrollController
        )
      }
      .padding(DemoMetrics.panelPadding)
    }
  }
}

struct PackageSourceListing: PrimitiveBlock {
  let theme: ChromaTheme
  let lines: [Substring]
  let scrollController: ScrollViewController

  init(theme: ChromaTheme, source: String, scrollController: ScrollViewController) {
    self.theme = theme
    self.lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    self.scrollController = scrollController
  }

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let metrics = FontMetrics()
    let longestLine = lines.map(\.utf8.count).max() ?? 0
    return Size(
      width: Float(longestLine + 5) * metrics.cellAdvance * DemoMetrics.textScale,
      height: Float(lines.count) * metrics.lineAdvance * DemoMetrics.textScale
    )
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let lineHeight = context.fontMetrics.lineAdvance * DemoMetrics.textScale
    context.withFocusGroup(.vertical, in: rect) {
      for (index, line) in lines.enumerated() {
        let lineRect = Rect(
          x: rect.minX,
          y: rect.minY + Float(index) * lineHeight,
          width: rect.size.width,
          height: lineHeight
        )
        let state = context.buttonState(
          id: WidgetID("package-line:\(index)"),
          in: lineRect
        )
        if state.hovered {
          drawList.fillRect(lineRect, color: theme.button.hoveredBackground)
          if !context.input.commands.isEmpty {
            scrollController.scrollToVisible(lineRect)
          }
        }
        let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        drawList.text(
          String(format: "%3d  %@", index + 1, String(line)),
          at: lineRect.origin,
          color: isComment ? theme.secondaryForeground : .white,
          scale: DemoMetrics.textScale
        )
      }
    }
  }
}
