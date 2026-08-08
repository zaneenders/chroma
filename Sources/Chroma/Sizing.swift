/// Describes how a block is sized along one axis.
public enum Sizing: Equatable, Sendable {
  /// Use the size required by the block's content.
  case fit

  /// Use exactly the specified size.
  case fixed(Float)

  /// Consume the space available from the parent layout.
  case grow
}
