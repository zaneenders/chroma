import Chroma
import Foundation

struct PackagePanel: Block {
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

struct PackageSourceListing: PrimitiveBlock {
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
