import Chroma

/// A read-only Markdown renderer with selectable text.
/// Links and images render their labels; emphasis renders without italic styling.
public struct MarkdownText: Block {
  public let document: MarkdownDocument
  public let scale: Float
  public let lineSpacing: Float

  @MainActor public init(_ markdown: String, scale: Float = 1, lineSpacing: Float = 4) {
    self.init(MarkdownDocument(markdown), scale: scale, lineSpacing: lineSpacing)
  }

  public init(_ document: MarkdownDocument, scale: Float = 1, lineSpacing: Float = 4) {
    precondition(scale.isFinite && scale > 0)
    precondition(lineSpacing.isFinite && lineSpacing >= 0)
    self.document = document
    self.scale = scale
    self.lineSpacing = lineSpacing
  }

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let blocks = document.blocks
    let revision = document.revision
    let preparation = document.layoutPreparation
    let content = VStack(spacing: 0) {
      ForEach(Array(blocks.indices), id: \.self) { index in
        MarkdownLeaf(
          block: blocks[index].block, scale: scale, lineSpacing: lineSpacing,
          hasLeadingGap: hasGap(before: index, in: blocks), parsedRuns: blocks[index].runs,
          preparation: preparation, source: (revision, index))
      }
    }
    return buffer.emit(content, context: context.component(Self.self))
  }

  private func hasGap(before index: Int, in blocks: [ParsedMarkdownBlock]) -> Bool {
    guard index > 0 else { return false }
    if case .listItem = blocks[index].block, case .listItem = blocks[index - 1].block { return false }
    return true
  }
}

struct MarkdownLeaf: Block {
  let block: MarkdownBlock
  let scale: Float
  let lineSpacing: Float
  var hasLeadingGap = false
  var parsedRuns: [MarkdownRun]?
  var preparation: MarkdownLayoutPreparation?
  var source: (revision: UInt64, index: Int)?

  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let context = context.component(Self.self)
    let preparation = preparation ?? MarkdownLayoutPreparation()
    return buffer.customLeaf(
      context: context, focusRule: .standard,
      expandsHorizontally: false, expandsVertically: false,
      measure: { proposal in
        let layout = preparation.resolve(self, in: Rect(origin: .zero, size: proposal), context: context)
        return Size(width: proposal.width, height: Float(layout.lines.count) * layout.lineHeight)
      },
      register: { rect in
        let layout = preparation.resolve(self, in: rect, context: context)
        _ = context.textSelectionState(
          in: rect, text: { layout.text },
          pointerOffset: { point, _ in layout.hitTest(point) },
          verticalOffset: { layout.verticalOffset($0, direction: $1) })
      },
      paint: { list, rect in
        preparation.resolve(self, in: rect, context: context).draw(
          into: &list, theme: context.theme, selection: context.textInputVisualState())
      })
  }
}
