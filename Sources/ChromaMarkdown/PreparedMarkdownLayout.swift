import Chroma

/// A single-entry cache owned by one resolved operation, never retained across operations.
/// Interaction closures retain value snapshots, not this mutable preparation.
@MainActor
final class MarkdownLayoutPreparation {
  private struct Key: Equatable {
    let block: MarkdownBlock
    let columns: Int
    let theme: ChromaTheme
    let metrics: FontMetrics
    let scale: Float
    let lineSpacing: Float
    let hasLeadingGap: Bool
  }

  private var cached: (key: Key, lines: [VisualLine])?
  // Deterministic, operation-local test hook; no global capture or lifetime extension.
  private(set) var layoutsBuilt = 0

  func resolve(_ leaf: MarkdownLeaf, in rect: Rect, context: BlockContext) -> MarkdownLayout {
    let effectiveScale = leaf.scale * context.textScale
    let metrics = context.fontMetrics
    let cellWidth = metrics.cellAdvance * effectiveScale
    let columns =
      rect.size.width.isFinite && cellWidth.isFinite && cellWidth > 0
      ? Int(min(Float(Int32.max), max(1, rect.size.width / cellWidth))) : Int(Int32.max)
    let key = Key(
      block: leaf.block, columns: columns, theme: context.theme, metrics: metrics,
      scale: effectiveScale, lineSpacing: leaf.lineSpacing, hasLeadingGap: leaf.hasLeadingGap)
    let lines: [VisualLine]
    if let cached, cached.key == key {
      lines = cached.lines
    } else {
      var result = layoutMarkdown(
        [leaf.block], columns: columns, theme: context.theme, baseColor: context.theme.foreground,
        parsedRuns: leaf.parsedRuns.map { [$0] })
      if leaf.hasLeadingGap { result.insert(VisualLine(), at: 0) }
      cached = (key, result)
      lines = result
      layoutsBuilt += 1
    }
    // Origins and the actual (possibly same-column) width belong to placement,
    // not shaping. Do not retain stale rectangles when reusing the line snapshot.
    return MarkdownLayout(
      lines: lines, lineHeight: metrics.lineAdvance * effectiveScale + leaf.lineSpacing,
      cellWidth: cellWidth, scale: effectiveScale, hasLeadingGap: leaf.hasLeadingGap, rect: rect)
  }
}
