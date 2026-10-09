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

struct MarkdownLeaf: LayoutPreparingBlock {
  let block: MarkdownBlock
  let scale: Float
  let lineSpacing: Float
  var hasLeadingGap = false

  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    PreparedMarkdownLeaf(leaf: self, preparation: MarkdownLayoutPreparation())
      .paint(into: &drawList, in: rect, context: context)
  }

  @MainActor func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    prepareLayout(context: context, preparation: MarkdownLayoutPreparation())
  }

  @MainActor func prepareLayout(
    context: BlockContext, preparation: MarkdownLayoutPreparation
  ) -> BlockEngine.Resolved {
    // Retain the ordinary primitive focus/identity behavior while sharing preparation
    // across this operation's measurement, registration, and paint closures.
    BlockEngine.prepare(
      PreparedMarkdownLeaf(leaf: self, preparation: preparation), context: context)
  }
}

private struct PreparedMarkdownLeaf: PaintableBlock {
  var preservesContentIdentity: Bool { true }
  var focusRule: FocusRule { .standard }
  let leaf: MarkdownLeaf
  let preparation: MarkdownLayoutPreparation

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    let layout = preparation.resolve(leaf, in: Rect(origin: .zero, size: proposal), context: context)
    return Size(width: proposal.width, height: Float(layout.lines.count) * layout.lineHeight)
  }

  @MainActor func register(in rect: Rect, context: BlockContext) {
    let layout = preparation.resolve(leaf, in: rect, context: context)
    _ = context.textSelectionState(
      in: rect, text: { layout.text },
      pointerOffset: { point, _ in layout.hitTest(point) },
      verticalOffset: { layout.verticalOffset($0, direction: $1) })
  }

  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    preparation.resolve(leaf, in: rect, context: context).draw(
      into: &drawList, theme: context.theme, selection: context.textInputVisualState())
  }
}
