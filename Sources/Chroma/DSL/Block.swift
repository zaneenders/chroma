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
  This function is a more flattend out version of optimizeTree as we need to flatten out those calls
  into one function to handle nested state correctly.
  */
  func parseTree(action: Bool, _ walker: inout some L2ElementWalker) -> L2Element {
    let l2: L2Element
    if let str = self as? String {
      l2 = .text(str, nil)
    } else if let text = self as? Text {
      l2 = .text(text.text, nil)
    } else if let inputBlock = self as? any InputBlock {
      // TODO: if selected && action, call handler.
      l2 = .text(inputBlock.wrapped, inputBlock.handler)
    } else if let group = self as? any BlockGroup {
      var l2Children: [L2Element] = []
      for child in group.children {
        l2Children.append(child.parseTree(action: action, &walker))
      }
      return .group(l2Children).flatten()
    } else {
      //TODO: self.restoreState(nodeKey: "\(self)")
      let group: L2Element = .group([self.layer.parseTree(action: action, &walker)])
        .flatten()
      /*
         TODO:
      if action {
        self.saveState(nodeKey: "\(self)")
      }*/
      return group
    }
    // Call the walking function on the resulting l2 element.
    l2._walk(&walker)
    return l2
  }
}
