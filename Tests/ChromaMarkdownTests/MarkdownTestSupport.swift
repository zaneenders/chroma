import Chroma

@testable import ChromaMarkdown

@MainActor
func markdownLeaf(
  _ document: MarkdownDocument, at index: Int = 0, scale: Float = 1, lineSpacing: Float = 4
) -> MarkdownLeaf {
  MarkdownLeaf(
    block: document.blocks[index], index: index, preparation: document.layoutPreparation,
    scale: scale, lineSpacing: lineSpacing)
}

func markdownLines(_ source: String, columns: Int = 80) -> [VisualLine] {
  segmentMarkdown(source).flatMap {
    layoutMarkdown(ParsedMarkdownBlock($0), columns: columns, colors: MarkdownColors(.dark)).lines
  }
}
