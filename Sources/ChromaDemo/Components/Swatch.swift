import Chroma
import Foundation

struct SwatchGrid: Block {
  let theme: ChromaTheme
  let state: DemoState

  var body: some Block {
    VStack(spacing: 8, alignment: .leading) {
      HStack(spacing: 6) {
        Swatch(label: "Blue", color: DemoPalette.blue, theme: theme, selected: state.accentName == "Blue") {
          state.accent = DemoPalette.blue
          state.accentName = "Blue"
        }
        Swatch(label: "Green", color: DemoPalette.green, theme: theme, selected: state.accentName == "Green") {
          state.accent = DemoPalette.green
          state.accentName = "Green"
        }
        Swatch(label: "Red", color: DemoPalette.red, theme: theme, selected: state.accentName == "Red") {
          state.accent = DemoPalette.red
          state.accentName = "Red"
        }
      }
      HStack(spacing: 6) {
        Swatch(label: "Yellow", color: theme.warning, theme: theme, selected: state.accentName == "Yellow") {
          state.accent = theme.warning
          state.accentName = "Yellow"
        }
        Swatch(label: "Orange", color: DemoPalette.orange, theme: theme, selected: state.accentName == "Orange") {
          state.accent = DemoPalette.orange
          state.accentName = "Orange"
        }
        Swatch(label: "Purple", color: DemoPalette.purple, theme: theme, selected: state.accentName == "Purple") {
          state.accent = DemoPalette.purple
          state.accentName = "Purple"
        }
      }
    }
  }
}

struct Swatch: Block {
  let label: String
  let color: Color
  let theme: ChromaTheme
  let selected: Bool
  let action: () -> Void

  var body: some Block {
    Interactive(id: "swatch:\(label)", action: action) { phase in
      VStack(spacing: 4, alignment: .leading) {
        color
          .frame(width: 26, height: 26)
          .border(selected ? Color.white : theme.border, width: selected ? 2 : 1)
        Text(label)
          .fontScale(DemoMetrics.textScale)
          .foregroundColor(selected ? .white : theme.secondaryForeground)
      }
      .padding(2)
      .background((phase == .idle ? .clear : Color(r: 1, g: 1, b: 1, a: phase == .hovered ? 0.06 : 0.12)))
    }
  }
}
