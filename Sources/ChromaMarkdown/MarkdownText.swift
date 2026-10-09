import Chroma

/// A read-only Markdown renderer with selectable text.
/// Links and images render their labels; emphasis renders without italic styling.
public struct MarkdownText {
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

  @MainActor public func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let context = context.component(Self.self)
    let blocks = document.blocks
    let preparation = document.layoutPreparation
    var children: [LayoutNode] = []
    children.reserveCapacity(blocks.count)
    for index in blocks.indices {
      let leaf = MarkdownLeaf(
        block: blocks[index], index: index, preparation: preparation,
        scale: scale, lineSpacing: lineSpacing)
      children.append(leaf.build(into: &buffer, context: context.keyed(index)))
    }
    return buffer.stack(children, axis: .vertical, context: context)
  }
}

struct MarkdownLeaf {
  let block: ParsedMarkdownBlock
  let index: Int
  let preparation: MarkdownLayoutPreparation
  let scale: Float
  let lineSpacing: Float

  @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let context = context.component(Self.self)
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
