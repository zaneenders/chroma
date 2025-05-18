public struct Group<B: Block>: Block, OrientationBlock {
  let orientation: Orientation
  let wrapped: B

  public init(_ orientation: Orientation, @BlockParser group: () -> B) {
    self.orientation = orientation
    self.wrapped = group()
  }

  public var layer: some Block {
    wrapped
  }
}

public enum Orientation {
  case horizontal
  case vertical
}

@MainActor
protocol OrientationBlock {
  var orientation: Orientation { get }
}
