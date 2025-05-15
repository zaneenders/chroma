public struct Navigation: Block {
  let items: [Item]
  public init(@NavigationBuilder navigationBuilder: () -> Navigation) {
    self = navigationBuilder()
  }

  fileprivate init(_ items: [Item]) {
    self.items = items
  }
}

public struct Item: NavigationItem {
  let b: any Block
  public init(@BlockParser elements: () -> some Block) {
    self.b = elements()
  }
}

extension Item {
  public var block: some Block {
    fatalError()
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
    -> Navigation
  {
    var _items: [Item] = []
    for item in repeat (each items) {
      let _item = item as! Item
      _items.append(_item)
    }
    return Navigation(_items)
  }
}
