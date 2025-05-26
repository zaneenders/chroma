public enum Location {
  case left
  case right
  case top
  case bottom
}

public struct Navigation: Block {
  let items: [Item]
  @State var selected = ""  // store hash
  let layout: Location

  // Navigation displays the content at the Location given. So if left is
  // passed in the navigation block is displayed on the left and the content is
  // displayed to the right in a horizontal layout.
  // if bottom is passed in the navigation is displayed at the bottom with the
  // content displayed above the navigation bar in a vertical fashion.
  public init(
    at location: Location,
    @NavigationBuilder navigationBuilder: () -> [Item]
  ) {
    self.items = navigationBuilder()
    self.layout = location
  }
}

extension Navigation {
  var orientation: Orientation {
    switch self.layout {
    case .bottom, .top:
      return .vertical
    case .left, .right:
      return .horizontal
    }
  }
}

public struct Item: NavigationItem {

  let label: String
  let content: any Block

  public init(
    label: String,
    @BlockParser content: () -> some Block
  ) {
    self.label = label
    self.content = content()
  }
}

extension Item {
  public var block: some Block {
    fatalError("Item has no block see Item.label and Item.content.")
  }
}

@MainActor
public protocol NavigationItem {
  associatedtype Item: Block
  @BlockParser var block: Item { get }
}

@MainActor
@resultBuilder
public enum NavigationBuilder {
  public static func buildBlock<each Element: NavigationItem>(
    _ items: repeat each Element
  )
    -> [Item]
  {
    var _items: [Item] = []
    for item in repeat (each items) {
      let _item = item as! Item
      _items.append(_item)
    }
    return _items
  }
}
