/// Text layout treatments backed by Chroma's bundled monospaced bitmap font.
///
/// Both cases use the same dependency-free glyph data. `display` is retained
/// as an API-compatible layout treatment for branding and terminal-style
/// accents; it may use a different configured advance.
public enum FontFace: UInt8, Equatable, Sendable {
  case readable
  case display
}
