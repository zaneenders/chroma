import Chroma

/// Immutable wrap plans only; rectangles and interaction callbacks belong to each operation.
/// Documents retain two style/width slots, with one line array per block in each slot.
@MainActor
final class MarkdownLayoutPreparation {
  private struct Key: Equatable {
    let revision: UInt64?
    let block: MarkdownBlock?
    let columns: Int
    let theme: ChromaTheme
    let metrics: FontMetrics
    let scale: Float
    let lineSpacing: Float
  }

  private struct Entry {
    let key: Key
    var blocks: [Int: (gap: Bool, lines: [VisualLine])] = [:]
  }

  private let capacity: Int
  private var cached: [Entry] = []
  private(set) var layoutsBuilt = 0
  var cachedPlanCount: Int { cached.count }
  var cachedBlockCount: Int { cached.reduce(0) { $0 + $1.blocks.count } }

  init(capacity: Int = 1) {
    precondition(capacity > 0)
    self.capacity = capacity
  }

  func resolve(_ leaf: MarkdownLeaf, in rect: Rect, context: LayoutContext) -> MarkdownLayout {
    let effectiveScale = leaf.scale * context.textScale
    let metrics = context.fontMetrics
    let cellWidth = metrics.cellAdvance * effectiveScale
    let columns =
      rect.size.width.isFinite && cellWidth.isFinite && cellWidth > 0
      ? Int(min(Float(Int32.max), max(1, rect.size.width / cellWidth))) : Int(Int32.max)
    let key = Key(
      revision: leaf.source?.revision, block: leaf.source == nil ? leaf.block : nil,
      columns: columns, theme: context.theme, metrics: metrics,
      scale: effectiveScale, lineSpacing: leaf.lineSpacing)
    let slot: Int
    if let found = cached.firstIndex(where: { $0.key == key }) {
      slot = found
    } else {
      if cached.count == capacity { cached.removeFirst() }
      cached.append(Entry(key: key))
      slot = cached.count - 1
    }
    let index = leaf.source?.index ?? 0
    let lines: [VisualLine]
    if let plan = cached[slot].blocks[index], plan.gap == leaf.hasLeadingGap {
      lines = plan.lines
    } else {
      var result = layoutMarkdown(
        [leaf.block], columns: columns, theme: context.theme, baseColor: context.theme.foreground,
        parsedRuns: leaf.parsedRuns.map { [$0] })
      if leaf.hasLeadingGap { result.insert(VisualLine(), at: 0) }
      cached[slot].blocks[index] = (leaf.hasLeadingGap, result)
      lines = result
      layoutsBuilt += 1
    }
    return MarkdownLayout(
      lines: lines, lineHeight: metrics.lineAdvance * effectiveScale + leaf.lineSpacing,
      cellWidth: cellWidth, scale: effectiveScale, hasLeadingGap: leaf.hasLeadingGap, rect: rect)
  }
}
