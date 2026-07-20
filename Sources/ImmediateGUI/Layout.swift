/// Horizontal alignment of a block inside its parent.
public enum HorizontalAlignment: Equatable, Sendable {
  case leading
  case center
  case trailing
}

/// Vertical alignment of a block inside its parent.
public enum VerticalAlignment: Equatable, Sendable {
  case top
  case center
  case bottom
}

/// A two-axis alignment used for placing blocks inside assigned space.
public struct Alignment: Equatable, Sendable {
  public var horizontal: HorizontalAlignment
  public var vertical: VerticalAlignment

  public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
    self.horizontal = horizontal
    self.vertical = vertical
  }

  public static let center = Alignment(horizontal: .center, vertical: .center)
  public static let leading = Alignment(horizontal: .leading, vertical: .center)
  public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
  public static let top = Alignment(horizontal: .center, vertical: .top)
  public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
  public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
}

extension Rect {
  /// Returns a rect of `size` placed inside this rect per `alignment`.
  func placing(_ size: Size, alignment: Alignment) -> Rect {
    let x: Float
    switch alignment.horizontal {
    case .leading: x = minX
    case .center: x = minX + (self.size.width - size.width) / 2
    case .trailing: x = maxX - size.width
    }
    let y: Float
    switch alignment.vertical {
    case .top: y = minY
    case .center: y = minY + (self.size.height - size.height) / 2
    case .bottom: y = maxY - size.height
    }
    return Rect(x: x, y: y, width: size.width, height: size.height)
  }
}

/// Insets applied by the `padding` modifier.
public struct EdgeInsets: Equatable, Sendable {
  public var top: Float
  public var leading: Float
  public var bottom: Float
  public var trailing: Float

  public init(top: Float = 0, leading: Float = 0, bottom: Float = 0, trailing: Float = 0) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }

  /// Equal insets on all edges.
  public init(_ amount: Float) {
    self.init(top: amount, leading: amount, bottom: amount, trailing: amount)
  }
}
