import Chroma
import Foundation

struct TabButton: Block {
  let label: String
  let selected: Bool
  let theme: ChromaTheme
  let accent: Color
  let action: () -> Void

  var body: some Block {
    Interactive(id: "tab:\(label)", action: action) { phase in
      Text(label)
        .fontScale(DemoMetrics.textScale)
        .foregroundColor(selected ? .white : theme.secondaryForeground)
        .padding(EdgeInsets(leading: 12, trailing: 12))
        .frame(height: DemoMetrics.itemHeight)
        .background(
          selected
            ? accent
            : (phase == .idle
              ? theme.button.idleBackground : phase == .hovered ? theme.button.hoveredBackground : accent)
        )
        .border(selected ? accent : theme.border, width: 1)
    }
  }
}
