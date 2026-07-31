public struct Text: PrimitiveBlock {
  public var content: String
  public var color: Color
  public var scale: Float
  public var isSelectable: Bool = false
  public var selectionID: WidgetID?

  public init(_ content: String) {
    self.content = content
    self.color = .white
    self.scale = 1
  }

  public func foregroundColor(_ color: Color) -> Text {
    var copy = self
    copy.color = color
    return copy
  }

  public func fontScale(_ scale: Float) -> Text {
    var copy = self
    copy.scale = scale
    return copy
  }

  public func selectable(_ id: WidgetID? = nil) -> Text {
    var copy = self
    copy.isSelectable = true
    copy.selectionID = id ?? WidgetID("text-select-\\(content.hashValue)")
    return copy
  }

  public func sizeThatFits(_ proposal: Size) -> Size {
    Interaction.current.fontMetrics.measure(content, scale: scale)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect) {
    if isSelectable, let id = selectionID {
      let interaction = Interaction.current
      let metrics = interaction.fontMetrics
      let cellWidth = metrics.cellAdvance * scale
      let lineHeight = metrics.lineAdvance * scale
      let layout = PlainTextLayout(
        text: content, rect: rect, cellWidth: cellWidth,
        lineHeight: lineHeight, scale: scale)
      interaction.textSelection.layoutRegistry.register(id, layout: layout)

      if let sel = interaction.textSelection.selection(for: layout) {
        let selX = rect.minX + Float(sel.from) * cellWidth
        let selW = Float(sel.to - sel.from) * cellWidth
        drawList.fillRect(
          Rect(x: selX, y: rect.minY, width: selW, height: lineHeight),
          color: Color(r: 0.3, g: 0.6, b: 1.0, a: 0.5))

        let prefix = content.prefix(sel.from)
        if !prefix.isEmpty {
          drawList.text(
            String(prefix), at: rect.origin, color: color, scale: scale)
        }
        let selected = content.dropFirst(sel.from).prefix(sel.to - sel.from)
        if !selected.isEmpty {
          let selOrigin = Point(x: rect.minX + Float(sel.from) * cellWidth, y: rect.minY)
          drawList.text(
            String(selected), at: selOrigin,
            color: Color(r: 1 - color.r, g: 1 - color.g, b: 1 - color.b, a: 1),
            scale: scale)
        }
        let suffix = content.dropFirst(sel.to)
        if !suffix.isEmpty {
          let suffixOrigin = Point(x: rect.minX + Float(sel.to) * cellWidth, y: rect.minY)
          drawList.text(
            String(suffix), at: suffixOrigin, color: color, scale: scale)
        }
        return
      }
    }
    drawList.text(content, at: rect.origin, color: color, scale: scale)
  }
}

extension Color: PrimitiveBlock {
  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }

  public func sizeThatFits(_ proposal: Size) -> Size { proposal }

  public func draw(into drawList: inout DrawList, in rect: Rect) {
    drawList.fillRect(rect, color: self)
  }
}

public struct EmptyBlock: PrimitiveBlock {
  public init() {}
  public func sizeThatFits(_ proposal: Size) -> Size { .zero }
  public func draw(into drawList: inout DrawList, in rect: Rect) {}
}

public struct Spacer: PrimitiveBlock {
  public init() {}

  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }

  public func sizeThatFits(_ proposal: Size) -> Size { proposal }
  public func draw(into drawList: inout DrawList, in rect: Rect) {}
}

public struct VStack: PrimitiveBlock {
  public var spacing: Float
  public var alignment: HorizontalAlignment
  public var children: [any Block]

  public init(
    spacing: Float = 0,
    alignment: HorizontalAlignment = .center,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.alignment = alignment
    self.children = BlockBuilder.flattenedChildren(content().children)
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { child in
      !(child is Spacer) && BlockEngine.expandsHorizontally(child)
    }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { BlockEngine.expandsVertically($0) }
  }

  @MainActor private func layout(proposal: Size) -> [Size] {
    var sizes = children.map { BlockEngine.measure($0, proposal: proposal) }
    for index in sizes.indices where children[index] is Spacer {
      sizes[index].width = 0
    }
    var fixedTotal: Float = 0
    var expanderCount = 0
    for (child, size) in zip(children, sizes) {
      if BlockEngine.expandsVertically(child) {
        expanderCount += 1
      } else {
        fixedTotal += size.height
      }
    }
    if expanderCount > 0 {
      let spacingTotal = spacing * Float(max(0, children.count - 1))
      let share = max(0, proposal.height - fixedTotal - spacingTotal) / Float(expanderCount)
      for index in sizes.indices where BlockEngine.expandsVertically(children[index]) {
        sizes[index].height = share
      }
    }
    return sizes
  }

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size {
    guard !children.isEmpty else { return .zero }
    let sizes = layout(proposal: proposal)
    let height = sizes.reduce(0) { $0 + $1.height } + spacing * Float(sizes.count - 1)
    let width = sizes.map(\.width).max() ?? 0
    return Size(width: width, height: height)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let sizes = layout(proposal: rect.size)
    let interaction = Interaction.current
    interaction.beginGroup(.vertical, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    var y = rect.minY
    for (child, size) in zip(children, sizes) {
      let width = min(size.width, rect.size.width)
      let x: Float
      switch alignment {
      case .leading: x = rect.minX
      case .center: x = rect.minX + (rect.size.width - width) / 2
      case .trailing: x = rect.maxX - width
      }
      BlockEngine.draw(child, into: &drawList, in: Rect(x: x, y: y, width: width, height: size.height))
      y += size.height + spacing
    }
    interaction.endGroup()
    if cursorOnGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}

public struct HStack: PrimitiveBlock {
  public var spacing: Float
  public var alignment: VerticalAlignment
  public var children: [any Block]

  public init(
    spacing: Float = 0,
    alignment: VerticalAlignment = .center,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.alignment = alignment
    self.children = BlockBuilder.flattenedChildren(content().children)
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { child in
      !(child is Spacer) && BlockEngine.expandsVertically(child)
    }
  }

  @MainActor private func layout(proposal: Size) -> [Size] {
    var sizes = children.map { BlockEngine.measure($0, proposal: proposal) }
    for index in sizes.indices where children[index] is Spacer {
      sizes[index].height = 0
    }
    var fixedTotal: Float = 0
    var expanderCount = 0
    for (child, size) in zip(children, sizes) {
      if BlockEngine.expandsHorizontally(child) {
        expanderCount += 1
      } else {
        fixedTotal += size.width
      }
    }
    if expanderCount > 0 {
      let spacingTotal = spacing * Float(max(0, children.count - 1))
      let share = max(0, proposal.width - fixedTotal - spacingTotal) / Float(expanderCount)
      for index in sizes.indices where BlockEngine.expandsHorizontally(children[index]) {
        sizes[index].width = share
      }
    }
    return sizes
  }

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size {
    guard !children.isEmpty else { return .zero }
    let sizes = layout(proposal: proposal)
    let width = sizes.reduce(0) { $0 + $1.width } + spacing * Float(sizes.count - 1)
    let height = sizes.map(\.height).max() ?? 0
    return Size(width: width, height: height)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let sizes = layout(proposal: rect.size)
    let interaction = Interaction.current
    interaction.beginGroup(.horizontal, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    var x = rect.minX
    for (child, size) in zip(children, sizes) {
      let height = min(size.height, rect.size.height)
      let y: Float
      switch alignment {
      case .top: y = rect.minY
      case .center: y = rect.minY + (rect.size.height - height) / 2
      case .bottom: y = rect.maxY - height
      }
      BlockEngine.draw(child, into: &drawList, in: Rect(x: x, y: y, width: size.width, height: height))
      x += size.width + spacing
    }
    interaction.endGroup()
    if cursorOnGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}

public struct ZStack: PrimitiveBlock {
  public var alignment: Alignment
  public var children: [any Block]

  public init(alignment: Alignment = .center, @BlockBuilder content: () -> TupleBlock) {
    self.alignment = alignment
    self.children = BlockBuilder.flattenedChildren(content().children)
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { BlockEngine.expandsVertically($0) }
  }

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size {
    var result = Size.zero
    for child in children {
      let size = BlockEngine.measure(child, proposal: proposal)
      result.width = max(result.width, size.width)
      result.height = max(result.height, size.height)
    }
    return result
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let interaction = Interaction.current
    interaction.beginGroup(.none, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    for child in children {
      let size = BlockEngine.measure(child, proposal: rect.size)
      BlockEngine.draw(child, into: &drawList, in: rect.placing(size, alignment: alignment))
    }
    interaction.endGroup()
    if cursorOnGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}
