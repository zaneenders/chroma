import Chroma
import Foundation

struct SectionTitle: Block {
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

struct KeyLegend: Block {
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
