import Chroma

/// Immutable wrap plans only; rectangles and interaction callbacks belong to each operation.
/// Documents retain two style/width slots, with one text/line/offset plan per block in each slot.
@MainActor
final class MarkdownLayoutPreparation {
  private struct Key: Equatable {
    let columns: Int
    let colors: MarkdownColors
  }

  private struct Entry {
    let key: Key
    var blocks: [Int: MarkdownLinePlan] = [:]
  }

  private var cached: [Entry] = []
  private(set) var layoutsBuilt = 0
  var cachedPlanCount: Int { cached.count }
  var cachedBlockCount: Int { cached.reduce(0) { $0 + $1.blocks.count } }

  func resolve(_ leaf: MarkdownLeaf, in rect: Rect, context: LayoutContext) -> MarkdownLayout {
    let effectiveScale = leaf.scale * context.textScale
    let metrics = context.fontMetrics
    let cellWidth = metrics.cellAdvance * effectiveScale
    let columns =
      rect.size.width.isFinite && cellWidth.isFinite && cellWidth > 0
      ? Int(min(Float(Int32.max), max(1, rect.size.width / cellWidth))) : Int(Int32.max)
    let key = Key(columns: columns, colors: MarkdownColors(context.theme))
    let slot: Int
    if let found = cached.firstIndex(where: { $0.key == key }) {
      slot = found
    } else {
      if cached.count == 2 { cached.removeFirst() }
      cached.append(Entry(key: key))
      slot = cached.count - 1
    }
    let plan: MarkdownLinePlan
    if let cachedPlan = cached[slot].blocks[leaf.index] {
      plan = cachedPlan
    } else {
      plan = layoutMarkdown(leaf.block, columns: columns, colors: key.colors)
      cached[slot].blocks[leaf.index] = plan
      layoutsBuilt += 1
    }
    return MarkdownLayout(
      plan: plan, lineHeight: metrics.lineAdvance * effectiveScale + leaf.lineSpacing,
      cellWidth: cellWidth, scale: effectiveScale, rect: rect)
  }
}
