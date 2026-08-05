import Chroma
import Foundation

struct CheckRow: Block {
  let label: String
  let isOn: Bool
  let theme: ChromaTheme
  let accent: Color
  let action: () -> Void

  var body: some Block {
    Interactive(id: "check:\(label)", action: action) { phase in
      HStack(spacing: 10, alignment: .center) {
        ZStack {
          isOn ? accent : theme.button.idleBackground
          if isOn {
            Text("+")
              .fontScale(DemoMetrics.textScale)
              .foregroundColor(.white)
          }
        }
        .frame(width: 20, height: 20)
        .border(isOn ? accent : theme.border, width: 1)

        Text(label)
          .fontScale(DemoMetrics.textScale)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: DemoMetrics.itemHeight, alignment: .leading)
      .padding(EdgeInsets(leading: 6))
      .background((phase == .idle ? .clear : Color(r: 1, g: 1, b: 1, a: phase == .hovered ? 0.06 : 0.12)))
    }
  }
}
