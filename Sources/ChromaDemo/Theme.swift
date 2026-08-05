import Chroma
import Foundation

struct Theme {
  var margin: Float = 12
  var spacing: Float = 8
  var panelPadding: Float = 12
  var headerHeight: Float = 42
  var statusHeight: Float = 26
  var itemHeight: Float = 32
  var textScale: Float = 0.5

  var background = Color(r: 0.045, g: 0.055, b: 0.075, a: 1)
  var panelBackground = Color(r: 0.065, g: 0.075, b: 0.10, a: 1)
  var headerBackground = Color(r: 0.075, g: 0.09, b: 0.13, a: 1)
  var statusBackground = Color(r: 0.04, g: 0.11, b: 0.09, a: 1)
  var border = Color(r: 0.16, g: 0.19, b: 0.25, a: 1)
  var buttonIdle = Color(r: 0.09, g: 0.11, b: 0.15, a: 1)
  var buttonHover = Color(r: 0.12, g: 0.16, b: 0.23, a: 1)
  var buttonPressed = Color(r: 0.18, g: 0.28, b: 0.42, a: 1)
  var textSecondary = Color(r: 0.52, g: 0.56, b: 0.66, a: 1)
  var blue = Color(r: 0.20, g: 0.62, b: 0.98, a: 1)
  var green = Color(r: 0.3, g: 0.8, b: 0.4, a: 1)
  var red = Color(r: 0.9, g: 0.3, b: 0.3, a: 1)
  var yellow = Color(r: 1, g: 0.85, b: 0.25, a: 1)
  var orange = Color(r: 1, g: 0.55, b: 0.15, a: 1)
  var purple = Color(r: 0.7, g: 0.3, b: 0.9, a: 1)

  func buttonColor(for phase: InteractionPhase, accent: Color) -> Color {
    switch phase {
    case .idle: buttonIdle
    case .hovered: buttonHover
    case .pressed: accent
    }
  }

  func highlightColor(for phase: InteractionPhase) -> Color {
    switch phase {
    case .idle: .clear
    case .hovered: Color(r: 1, g: 1, b: 1, a: 0.06)
    case .pressed: Color(r: 1, g: 1, b: 1, a: 0.12)
    }
  }
}
