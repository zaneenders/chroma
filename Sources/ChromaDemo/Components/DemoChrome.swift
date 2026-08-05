import Chroma
import Foundation

struct SectionTitle: Block {
  let title: String
  let theme: ChromaTheme

  var body: some Block {
    Text(title)
      .fontScale(DemoMetrics.textScale)
      .foregroundColor(theme.secondaryForeground)
      .frame(height: DemoMetrics.itemHeight, alignment: .leading)
      .padding(EdgeInsets(bottom: DemoMetrics.spacing))
  }
}

struct KeyLegend: Block {
  let theme: ChromaTheme

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
  fileprivate func legendStyle(_ theme: ChromaTheme) -> Text {
    fontScale(DemoMetrics.textScale).foregroundColor(theme.secondaryForeground)
  }
}
