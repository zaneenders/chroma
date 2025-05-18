/// The ``Block`` protocol is used to compose your own custom blocks. You can build up more complex Blocks using String literals and the ``bind(key:action:)`` function to add
/// interactivity.
@MainActor  // This is required to force ``Block``s to be processed on the main thread allowing for other actions to be performed on other threads/actors.
public protocol Block {
  associatedtype Component: Block
  @BlockParser var layer: Component { get }
}

extension Block where Component == Never {
  public var layer: Never {
    fatalError("\(Self.self):\(#fileID):\(#function)")
  }
}

extension Never: Block {
  public var layer: some Block {
    fatalError("\(Self.self):\(#fileID):\(#function)")
  }
}

extension Block {

  func collectChildren() -> [any Block] {
    if self is String {
      return [self]
    } else if self is Text {
      return [self]
    } else if self is any InputBlock {
      return [self]
    } else if let group = self as? any BlockGroup {
      return group.children.flatMap { $0.collectChildren() }
      // NOTE: not sure if I need this second collection if this is called as a flatMap, see notes for original.
      // var children: [any Block] = []
      // for child in _children {
      //   children += child.collectChildren()
      // }
      // return children
    } else {
      return self.layer.collectChildren()
    }
  }

  /*
  This function is a more flattened out version of optimizeTree as we need to flatten out those calls
  into one function to handle nested state correctly.
  */
  func parseTree(action: Bool, _ walker: inout some ElementWalker) {
    if let str = self as? String {
      walker.walkText(str, nil)
    } else if let textBlock = self as? Text {
      walker.walkText(textBlock.text, nil)
    } else if let inputBlock = self as? any InputBlock {
      walker.walkText(inputBlock.wrapped, inputBlock.handler)
    } else if let group = self as? any OrientationBlock {
      let current = walker.orientation
      walker.orientation = group.orientation
      self.layer.parseTree(action: action, &walker)
      walker.orientation = current
    } else if let group = self as? any BlockGroup {
      let ourHash = walker.currentHash
      let children = group.children.flatMap { $0.collectChildren() }
      walker.beforeGroup(childrenCount: children.count)
      child_loop: for (index, child) in children.enumerated() {
        if walker.beforeChild() {
          break child_loop
        }
        walker.currentHash = hash(contents: "\(ourHash)\(#function)\(index)")
        child.parseTree(action: action, &walker)
        if walker.afterChild(
          nextChildHash: hash(contents: "\(ourHash)\(#function)\(index + 1)"),
          prevChildHash: hash(contents: "\(ourHash)\(#function)\(index - 1)"),
          index: index,
          childCount: children.count)
        {
          break child_loop
        }
      }
      walker.afterGroup(ourHash: ourHash)
      walker.currentHash = ourHash
      return
    } else {
      self.restoreState(nodeKey: "\(self)")
      let ourHash = walker.currentHash
      walker.currentHash = hash(contents: "\(ourHash)\(#function)\(0)")
      walker.beforeGroup(childrenCount: 1)
      let skip = walker.beforeChild()
      if !skip {
        self.layer.parseTree(action: action, &walker)
      }
      _ = walker.afterChild(
        // is this even valid here, only one child no next or prev child.
        nextChildHash: hash(contents: "\(ourHash)\(#function)\(1)"),
        prevChildHash: hash(contents: "\(ourHash)\(#function)\(-1)"),
        index: 0, childCount: 1)
      walker.afterGroup(ourHash: ourHash)
      walker.currentHash = ourHash
      if action {
        self.saveState(nodeKey: "\(self)")
      }
      return
    }
  }
}
