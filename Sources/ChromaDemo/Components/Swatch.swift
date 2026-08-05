import Chroma
import Foundation

struct SwatchGrid: Block {
  let theme: Theme
  let state: DemoState

  var body: some Block {
    VStack(spacing: 8, alignment: .leading) {
      HStack(spacing: 6) {
        Swatch(label: "Blue", color: theme.blue, theme: theme, selected: state.accentName == "Blue") {
          state.accent = theme.blue
          state.accentName = "Blue"
        }
        Swatch(label: "Green", color: theme.green, theme: theme, selected: state.accentName == "Green") {
          state.accent = theme.green
          state.accentName = "Green"
        }
        Swatch(label: "Red", color: theme.red, theme: theme, selected: state.accentName == "Red") {
          state.accent = theme.red
          state.accentName = "Red"
        }
      }
      HStack(spacing: 6) {
        Swatch(label: "Yellow", color: theme.yellow, theme: theme, selected: state.accentName == "Yellow") {
          state.accent = theme.yellow
          state.accentName = "Yellow"
        }
        Swatch(label: "Orange", color: theme.orange, theme: theme, selected: state.accentName == "Orange") {
          state.accent = theme.orange
          state.accentName = "Orange"
        }
        Swatch(label: "Purple", color: theme.purple, theme: theme, selected: state.accentName == "Purple") {
          state.accent = theme.purple
          state.accentName = "Purple"
        }
      }
    }
  }
}

struct Swatch: Block {
  let label: String
  let color: Color
  let theme: Theme
  let selected: Bool
  let action: () -> Void

  var body: some Block {
    Interactive(id: "swatch:\(label)", action: action) { phase in
      VStack(spacing: 4, alignment: .leading) {
        color
          .frame(width: 26, height: 26)
          .border(selected ? Color.white : theme.border, width: selected ? 2 : 1)
        Text(label)
          .fontScale(theme.textScale)
          .foregroundColor(selected ? .white : theme.textSecondary)
      }
      .padding(2)
      .background(theme.highlightColor(for: phase))
    }
  }
}
