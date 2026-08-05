import Chroma

// Layout tokens are demo-specific; colors and control states come from ChromaTheme.
enum DemoMetrics {
  static let margin: Float = 12
  static let spacing: Float = 8
  static let panelPadding: Float = 12
  static let headerHeight: Float = 42
  static let statusHeight: Float = 26
  static let itemHeight: Float = 32
  static let textScale: Float = 0.5
}

enum DemoPalette {
  static let blue = Color(r: 0.20, g: 0.62, b: 0.98, a: 1)
  static let green = Color(r: 0.3, g: 0.8, b: 0.4, a: 1)
  static let red = Color(r: 0.9, g: 0.3, b: 0.3, a: 1)
  static let yellow = Color(r: 1, g: 0.85, b: 0.25, a: 1)
  static let orange = Color(r: 1, g: 0.55, b: 0.15, a: 1)
  static let purple = Color(r: 0.7, g: 0.3, b: 0.9, a: 1)
}
