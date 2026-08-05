import Chroma
import Foundation

struct DemoButton: Block {
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
