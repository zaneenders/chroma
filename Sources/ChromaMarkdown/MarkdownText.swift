import Chroma

/// A read-only Markdown renderer with selectable text.
/// Links and images render their labels; emphasis renders without italic styling.
public struct MarkdownText: Block {
  public var markdown: String
  public let scale: Float
  public let lineSpacing: Float

  public init(_ markdown: String, scale: Float = 1, lineSpacing: Float = 4) {
    precondition(scale.isFinite && scale > 0)
    precondition(lineSpacing.isFinite && lineSpacing >= 0)
    self.markdown = markdown
    self.scale = scale
    self.lineSpacing = lineSpacing
  }

  @MainActor public var body: some Block {
    let blocks = segmentMarkdown(markdown)
    return VStack(spacing: 0) {
      ForEach(Array(blocks.indices), id: \.self) { index in
        MarkdownLeaf(
          block: blocks[index], scale: scale, lineSpacing: lineSpacing,
          hasLeadingGap: hasGap(before: index, in: blocks))
      }
    }
  }

  private func hasGap(before index: Int, in blocks: [MarkdownBlock]) -> Bool {
    guard index > 0 else { return false }
    if case .listItem = blocks[index], case .listItem = blocks[index - 1] { return false }
    return true
  }
}

struct MarkdownLeaf: PaintableBlock {
  var focusRule: FocusRule { .standard }
  let block: MarkdownBlock
  let scale: Float
  let lineSpacing: Float
  var hasLeadingGap = false

  @MainActor private func layout(in rect: Rect, context: BlockContext) -> MarkdownLayout {
    let effectiveScale = scale * context.textScale
    let cellWidth = context.fontMetrics.cellAdvance * effectiveScale
    let columns =
      rect.size.width.isFinite && cellWidth.isFinite && cellWidth > 0
      ? Int(min(Float(Int32.max), max(1, rect.size.width / cellWidth))) : Int(Int32.max)
    var lines = layoutMarkdown(
      [block], columns: columns, theme: context.theme,
      baseColor: context.theme.foreground)
    if hasLeadingGap { lines.insert(VisualLine(), at: 0) }
    return MarkdownLayout(
      lines: lines,
      lineHeight: context.fontMetrics.lineAdvance * effectiveScale + lineSpacing,
      cellWidth: cellWidth, scale: effectiveScale, hasLeadingGap: hasLeadingGap, rect: rect)
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    let layout = layout(in: Rect(origin: .zero, size: proposal), context: context)
    return Size(width: proposal.width, height: Float(layout.lines.count) * layout.lineHeight)
  }

  @MainActor public func register(in rect: Rect, context: BlockContext) {
    let layout = layout(in: rect, context: context)
    _ = context.textSelectionState(
      in: rect, text: { layout.text },
      pointerOffset: { point, _ in layout.hitTest(point) },
      verticalOffset: { layout.verticalOffset($0, direction: $1) })
  }

  @MainActor public func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    layout(in: rect, context: context).draw(
      into: &drawList, theme: context.theme, selection: context.textInputVisualState())
  }
}
