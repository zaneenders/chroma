import Observation

/// Keep a document in your model to parse Markdown only when its source changes.
@Observable
@MainActor
public final class MarkdownDocument {
  public var markdown: String {
    didSet {
      guard !markdown.utf8.elementsEqual(oldValue.utf8) else { return }
      blocks = segmentMarkdown(markdown).map(ParsedMarkdownBlock.init)
      revision += 1
    }
  }

  public private(set) var revision: UInt64 = 0
  private(set) var blocks: [ParsedMarkdownBlock]

  public init(_ markdown: String) {
    self.markdown = markdown
    blocks = segmentMarkdown(markdown).map(ParsedMarkdownBlock.init)
  }
}

struct ParsedMarkdownBlock {
  let block: MarkdownBlock
  let runs: [MarkdownRun]

  init(_ block: MarkdownBlock) {
    self.block = block
    switch block {
    case .paragraph(let text), .heading(_, let text), .listItem(_, let text, _), .quote(let text):
      runs = inlineRuns(text)
    case .code, .rule:
      runs = []
    }
  }
}
