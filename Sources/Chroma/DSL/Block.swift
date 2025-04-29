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
  /*
  This function is a more flattened out version of optimizeTree as we need to flatten out those calls
  into one function to handle nested state correctly.
  */
  func parseTree(action: Bool, _ walker: inout some L2ElementWalker) {
    if let str = self as? String {
      walker.walkText(str, nil)
    } else if let textBlock = self as? Text {
      walker.walkText(textBlock.text, nil)
    } else if let inputBlock = self as? any InputBlock {
      // TODO: if selected && action, call handler.
      walker.walkText(inputBlock.wrapped, inputBlock.handler)
    } else if let group = self as? any BlockGroup {
      let ourHash = walker.currentHash
      walker.beforeGroup(group.children)
      child_loop: for (index, child) in group.children.enumerated() {
        if walker.beforeChild() {
          break child_loop
        }
        walker.currentHash = hash(contents: "\(ourHash)\(#function)\(index)")
        child.parseTree(action: action, &walker)
        if walker.afterChild(
          nextChildHash: hash(contents: "\(ourHash)\(#function)\(index + 1)"),
          prevChildHash: hash(contents: "\(ourHash)\(#function)\(index - 1)"),
          index: index,
          childCount: group.children.count)
        {
          break child_loop
        }
      }
      walker.afterGroup(ourHash: ourHash, group.children)
      walker.currentHash = ourHash
      return
    } else {
      self.restoreState(nodeKey: "\(self)")
      let ourHash = walker.currentHash
      walker.currentHash = hash(contents: "\(ourHash)\(#function)\(0)")
      walker.beforeGroup([self.layer])
      let skip = walker.beforeChild()
      self.layer.parseTree(action: action, &walker)
      _ = walker.afterChild(
        // is this even valid here?
        nextChildHash: hash(contents: "\(ourHash)\(#function)\(1)"),
        prevChildHash: hash(contents: "\(ourHash)\(#function)\(-1)"),
        index: 0, childCount: 1)
      walker.afterGroup(ourHash: ourHash, [self.layer])
      walker.currentHash = ourHash
      if action {
        self.saveState(nodeKey: "\(self)")
      }
      return
    }
  }
}
