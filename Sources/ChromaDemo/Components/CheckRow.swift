import Chroma
import Foundation

struct CheckRow: Block {
  let label: String
  let isOn: Bool
  let theme: Theme
  let accent: Color
  let action: () -> Void

  var body: some Block {
    Interactive(id: "check:\(label)", action: action) { phase in
      HStack(spacing: 10, alignment: .center) {
        ZStack {
          isOn ? accent : theme.buttonIdle
          if isOn {
            Text("+")
              .fontScale(theme.textScale)
              .foregroundColor(.white)
          }
        }
        .frame(width: 20, height: 20)
        .border(isOn ? accent : theme.border, width: 1)

        Text(label)
          .fontScale(theme.textScale)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: theme.itemHeight, alignment: .leading)
      .padding(EdgeInsets(leading: 6))
      .background(theme.highlightColor(for: phase))
    }
  }
}
