/// A run of text in the built-in bitmap font.
public struct Text: PrimitiveBlock {
  public var content: String
  public var color: Color
  public var scale: Float

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

  public func sizeThatFits(_ proposal: Size) -> Size {
    FontMetrics().measure(content, scale: scale)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect) {
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

/// A block that draws nothing. Placeholder for optional content.
public struct EmptyBlock: PrimitiveBlock {
  public init() {}
  public func sizeThatFits(_ proposal: Size) -> Size { .zero }
  public func draw(into drawList: inout DrawList, in rect: Rect) {}
}

/// Flexible space. Inside a stack it takes an equal share of the leftover
/// space along the stack axis; elsewhere it fills its proposal.
public struct Spacer: PrimitiveBlock {
  public init() {}

  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }

  public func sizeThatFits(_ proposal: Size) -> Size { proposal }
  public func draw(into drawList: inout DrawList, in rect: Rect) {}
}

/// A vertical stack of blocks with spacing and horizontal alignment.
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
    self.children = content().children
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { BlockEngine.expandsVertically($0) }
  }

  /// Child sizes against `proposal`: fixed children keep their measured
  /// height; expanding children split the leftover height equally.
  @MainActor private func layout(proposal: Size) -> [Size] {
    var sizes = children.map { BlockEngine.measure($0, proposal: proposal) }
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
  }
}

/// A horizontal stack of blocks with spacing and vertical alignment.
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
    self.children = content().children
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { BlockEngine.expandsVertically($0) }
  }

  /// Child sizes against `proposal`: fixed children keep their measured
  /// width; expanding children split the leftover width equally.
  @MainActor private func layout(proposal: Size) -> [Size] {
    var sizes = children.map { BlockEngine.measure($0, proposal: proposal) }
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
  }
}

/// A stack that layers its children on top of each other, back to front.
public struct ZStack: PrimitiveBlock {
  public var alignment: Alignment
  public var children: [any Block]

  public init(alignment: Alignment = .center, @BlockBuilder content: () -> TupleBlock) {
    self.alignment = alignment
    self.children = content().children
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
    for child in children {
      let size = BlockEngine.measure(child, proposal: rect.size)
      BlockEngine.draw(child, into: &drawList, in: rect.placing(size, alignment: alignment))
    }
  }
}
