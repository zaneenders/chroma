/// Scroll construction with direct row factories. Block conveniences use these same stored builders.
extension LayoutBuffer {
  public mutating func scrollView(
    _ name: String? = nil, showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController? = nil, context: BlockContext, build: @escaping LayoutBuilder
  ) -> LayoutNode {
    scrollView(
      ScrollView(
        name, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller, build: build),
      context: context)
  }

  public mutating func scrollView(
    _ name: String? = nil, spacing: Float = 0, showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, rows: [ScrollView.Row], context: BlockContext
  ) -> LayoutNode {
    scrollView(
      ScrollView(
        name, spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
        controller: controller, rows: rows), context: context)
  }

  public mutating func scrollView<Data: RandomAccessCollection>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, identityRevision: UInt64? = nil, context: BlockContext,
    build: @escaping ScrollView.RowBuilder<Data.Element>
  ) -> LayoutNode {
    scrollView(
      ScrollView(
        name, data: data, rowHeight: rowHeight, spacing: spacing,
        showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
        controller: controller, identityRevision: identityRevision, build: build), context: context)
  }

  /// Change identityRevision whenever IDs or their order change, including same-count edits.
  public mutating func scrollView<Data: RandomAccessCollection>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, identityRevision: UInt64? = nil, context: BlockContext,
    build: @escaping ScrollView.RowBuilder<Data.Element>
  ) -> LayoutNode where Data.Element: Identifiable, Data.Element.ID: Sendable {
    scrollView(
      ScrollView(
        name, data: data, rowHeight: rowHeight, spacing: spacing,
        showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
        controller: controller, identityRevision: identityRevision, build: build), context: context)
  }

  public mutating func scrollView<Data: RandomAccessCollection>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, selection: ScrollSelection<Data.Element.ID>, identityRevision: UInt64? = nil,
    context: BlockContext, build: @escaping ScrollView.RowBuilder<Data.Element>
  ) -> LayoutNode where Data.Element: Identifiable, Data.Element.ID: Sendable {
    scrollView(
      ScrollView(
        name, data: data, rowHeight: rowHeight, spacing: spacing,
        showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
        controller: controller, selection: selection, identityRevision: identityRevision, build: build),
      context: context)
  }
}
