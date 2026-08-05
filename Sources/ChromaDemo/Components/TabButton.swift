import Chroma
import Foundation

struct TabButton: Block {
  let label: String
  let selected: Bool
  let theme: Theme
  let accent: Color
  let action: () -> Void

  var body: some Block {
    Interactive(id: "tab:\(label)", action: action) { phase in
      Text(label)
        .fontScale(theme.textScale)
        .foregroundColor(selected ? .white : theme.textSecondary)
        .padding(EdgeInsets(leading: 12, trailing: 12))
        .frame(height: theme.itemHeight)
        .background(selected ? accent : theme.buttonColor(for: phase, accent: accent))
        .border(selected ? accent : theme.border, width: 1)
    }
  }
}
