@MainActor
final class NodeScene {
  enum BuildError: Error {
    case unsupportedBlock
  }

  private enum Content {
    case text(Text)
    case button(Button)
  }

  private struct Node {
    var content: Content
    var context: BlockContext
    var rect: Rect = .zero
    var lines: [String] = []
  }

  private var store = NodeStore<Node>()
  private var root: NodeID?
  private var laidOut = false
  private var prepared = false

  func update(_ block: any Block, context: BlockContext) throws {
    let node = try lower(block, context: context)
    if let root {
      store.update(root, value: node)
    } else {
      root = store.insert(node)
    }
    laidOut = false
    prepared = false
  }

  private func lower(_ block: any Block, context: BlockContext) throws -> Node {
    if let scoped = block as? ScopedBlock {
      return try lower(scoped.content, context: context.scoped(scoped.path))
    }
    let context = context.scoped([.component(ObjectIdentifier(type(of: block)))])
    if let text = block as? Text {
      guard !text.isSelectable else { throw BuildError.unsupportedBlock }
      return Node(content: .text(text), context: context)
    }
    if let button = block as? Button {
      return Node(content: .button(button), context: context)
    }
    guard !(block is any PrimitiveBlock) else { throw BuildError.unsupportedBlock }
    return try lower(block.body, context: context)
  }

  @discardableResult
  func layout(in rect: Rect) -> Size {
    guard let root, var node = store.value(for: root) else { return .zero }
    node.rect = rect
    let size: Size
    switch node.content {
    case .text(let text):
      size = text.sizeThatFits(rect.size, context: node.context)
      let cell = node.context.fontMetrics.cellAdvance * text.scale * node.context.textScale
      let columns =
        text.wraps && rect.size.width.isFinite && cell.isFinite && cell > 0
        ? Int(min(Float(Int32.max), max(1, rect.size.width / cell))) : nil
      node.lines = TextLayout(text.content, columns: columns).lines.map(\.text)
    case .button(let button):
      size = button.sizeThatFits(rect.size, context: node.context)
    }
    store.update(root, value: node)
    laidOut = true
    prepared = false
    return size
  }

  func prepare(viewport: Size) {
    precondition(laidOut, "Layout must precede interaction preparation")
    guard let root, let node = store.value(for: root) else { return }
    let interaction = node.context.interaction
    interaction.viewport = Rect(origin: .zero, size: viewport)
    interaction.beginFrame(input: interaction.input, processingInput: false)
    switch node.content {
    case .text:
      if !node.context.focusLeafClaimed && !node.context.navigationIgnored {
        _ = node.context.buttonState(id: node.context.widgetID, in: node.rect)
      }
    case .button(let button):
      _ = node.context.buttonState(
        id: button.id ?? node.context.widgetID, in: node.rect, role: button.role, action: button.action)
    }
    interaction.endFrame()
    prepared = true
  }

  func dispatch(_ input: InputState) {
    precondition(prepared, "Interaction preparation must precede input")
    guard let root, let node = store.value(for: root) else { return }
    node.context.interaction.processInput(input)
    node.context.interaction.finishInput()
  }

  func paint() -> DrawList {
    precondition(prepared, "Interaction preparation must precede paint")
    var list = DrawList()
    guard let root, let node = store.value(for: root) else { return list }
    switch node.content {
    case .text(let text):
      let scale = text.scale * node.context.textScale
      for (row, line) in node.lines.enumerated() {
        list.text(
          line,
          at: Point(
            x: node.rect.minX,
            y: node.rect.minY + Float(row)
              * node.context.fontMetrics.lineAdvance * scale), color: text.color, scale: scale)
      }
      if !node.context.focusLeafClaimed && !node.context.navigationIgnored {
        BlockEngine.drawHighlight(
          for: node.context.widgetID, into: &list, in: node.rect, context: node.context)
      }
    case .button(let button):
      let interaction = node.context.interaction
      let id = button.id ?? node.context.widgetID
      let state = interaction.untrackedLeafState
      button.paint(
        into: &list, in: node.rect, context: node.context,
        state: ButtonState(
          hovered: state.hovered == id, focused: state.selected == id,
          held: state.pressed == id && interaction.input.pointerDown, clicked: false))
    }
    return list
  }
}
