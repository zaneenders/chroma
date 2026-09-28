public struct ScrollView: PrimitiveBlock {
  public struct Row: Identifiable {
    public let id: AnyHashable
    public var content: any Block {
      didSet { measurementIdentity = LazyRowIdentity() }
    }
    // Copies retain measurements; replacing content or constructing a row invalidates them.
    var measurementIdentity = LazyRowIdentity()
    let key: StructuralKey

    public init(id: some Hashable & Sendable, content: any Block) {
      self.id = AnyHashable(id)
      self.key = StructuralKey(id)
      self.content = content
    }
  }

  private var virtualRows: VirtualRows?

  var id: WidgetID?
  public var name: String? = nil
  public var showsIndicator: Bool
  public var sticksToBottom: Bool
  public var controller: ScrollViewController?
  public var content: any Block

  init(
    id: WidgetID?,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController? = nil,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.id = id
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = VStack(content: content)
  }

  public init(
    _ name: String? = nil,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController? = nil,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.init(
      id: nil, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller, content: content)
    self.name = name
  }

  init(
    id: WidgetID?,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    rows: [Row]
  ) {
    self.id = id
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = EmptyBlock()
    self.virtualRows = VirtualRows(
      id: id, spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller,
      rows: rows)
  }

  public init(
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    rows: [Row]
  ) {
    self.id = nil
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = EmptyBlock()
    self.virtualRows = VirtualRows(
      spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller,
      rows: rows)
  }

  @MainActor init<Data: RandomAccessCollection, Content: Block>(
    id: WidgetID?,
    data: Data,
    rowHeight: Float,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.id = id
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = EmptyBlock()
    self.virtualRows = VirtualRows(
      id: id, data: data, rowHeight: rowHeight, spacing: spacing, showsIndicator: showsIndicator,
      sticksToBottom: sticksToBottom, controller: controller, content: content)
  }

  @MainActor public init<Data: RandomAccessCollection, Content: Block>(
    data: Data,
    rowHeight: Float,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.id = nil
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = EmptyBlock()
    self.virtualRows = VirtualRows(
      data: data, rowHeight: rowHeight, spacing: spacing, showsIndicator: showsIndicator,
      sticksToBottom: sticksToBottom, controller: controller, content: content)
  }

  @MainActor init<Data: RandomAccessCollection, Content: Block>(
    id: WidgetID?,
    data: Data,
    rowHeight: Float,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    self.id = id
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = EmptyBlock()
    self.virtualRows = VirtualRows(
      id: id, data: data, rowHeight: rowHeight, spacing: spacing, showsIndicator: showsIndicator,
      sticksToBottom: sticksToBottom, controller: controller, content: content)
  }

  @MainActor public init<Data: RandomAccessCollection, Content: Block>(
    data: Data,
    rowHeight: Float,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    self.id = nil
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = EmptyBlock()
    self.virtualRows = VirtualRows(
      data: data, rowHeight: rowHeight, spacing: spacing, showsIndicator: showsIndicator,
      sticksToBottom: sticksToBottom, controller: controller, content: content)
  }

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { true }
  @MainActor public var expandsVertically: Bool { true }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    if var rows = virtualRows {
      rows.id = id
      rows.showsIndicator = showsIndicator
      rows.sticksToBottom = sticksToBottom
      if let controller { rows.controller = controller }
      rows.draw(into: &drawList, in: rect, context: context)
      return
    }
    let id = id ?? context.widgetID
    let interaction = context.interaction
    controller?.restore(id: id, interaction: interaction)
    interaction.registerScrollInput(id: id, rect: rect, horizontal: true)
    let contentSize = BlockEngine.measure(
      content,
      proposal: Size(
        width: rect.size.width,
        height: Float.greatestFiniteMagnitude
      ), context: context)
    let offsets = interaction.resolveScroll(
      id: id, viewport: rect, contentSize: contentSize, controller: controller,
      sticksToBottom: sticksToBottom, horizontal: true)
    let offset = offsets.y
    let horizontalOffset = offsets.x
    let maximumOffset = max(0, contentSize.height - rect.size.height)
    let maximumHorizontalOffset = max(0, contentSize.width - rect.size.width)

    drawList.pushClip(rect)
    interaction.pushClip(rect)
    interaction.beginGroup(rect: rect, scrollID: id, navigationID: id, navigationName: name)
    BlockEngine.draw(
      content,
      into: &drawList,
      in: Rect(
        x: rect.minX - horizontalOffset, y: rect.minY - offset,
        width: contentSize.width, height: contentSize.height), context: context)
    interaction.endGroup()
    interaction.popClip()

    let style = context.theme.scrollView
    if showsIndicator && maximumOffset > 0 && rect.size.height > 0 {
      let trackWidth = style.indicatorThickness
      let thumbHeight = max(style.minimumThumbLength, rect.size.height * rect.size.height / contentSize.height)
      let travel = rect.size.height - thumbHeight
      let thumbY = rect.minY + travel * (offset / maximumOffset)
      drawList.fillRect(
        Rect(x: rect.maxX - trackWidth, y: thumbY, width: trackWidth, height: thumbHeight),
        color: style.indicator
      )
    }
    if showsIndicator && maximumHorizontalOffset > 0 && rect.size.width > 0 {
      let trackHeight = style.indicatorThickness
      let thumbWidth = max(style.minimumThumbLength, rect.size.width * rect.size.width / contentSize.width)
      let travel = rect.size.width - thumbWidth
      let thumbX = rect.minX + travel * (horizontalOffset / maximumHorizontalOffset)
      drawList.fillRect(
        Rect(x: thumbX, y: rect.maxY - trackHeight, width: thumbWidth, height: trackHeight),
        color: style.indicator
      )
    }
    drawList.popClip()
  }
}
