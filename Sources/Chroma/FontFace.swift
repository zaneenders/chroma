/// The two text treatments shipped by Chroma.
///
/// `readable` uses the platform monospaced system face in graphical backends.
/// `display` preserves Chroma's hand-authored bitmap face for branding and
/// terminal-style accents.
public enum FontFace: UInt8, Equatable, Sendable {
  case readable
  case display
}
