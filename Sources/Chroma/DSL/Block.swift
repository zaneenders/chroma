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
    let text: L2Element
    if let str = self as? String {
      text = .text(str, nil)
    } else if let textBlock = self as? Text {
      text = .text(textBlock.text, nil)
    } else if let inputBlock = self as? any InputBlock {
      // TODO: if selected && action, call handler.
      text = .text(inputBlock.wrapped, inputBlock.handler)
    } else if let group = self as? any BlockGroup {
      for child in group.children {
        child.parseTree(action: action, &walker)
      }
      return
    } else {
      self.restoreState(nodeKey: "\(self)")
      self.layer.parseTree(action: action, &walker)
      if action {
        self.saveState(nodeKey: "\(self)")
      }
      return
    }
    text._walk(&walker)
  }
}
