import Observation

/// Keep a document in your model to reuse parsing and two bounded width/style wrap plans.
@Observable
@MainActor
public final class MarkdownDocument {
  public var markdown: String {
    didSet {
      guard !markdown.utf8.elementsEqual(oldValue.utf8) else { return }
      blocks = parseMarkdown(markdown)
      revision += 1
      layoutPreparation = MarkdownLayoutPreparation()
    }
  }

  public private(set) var revision: UInt64 = 0
  private(set) var blocks: [ParsedMarkdownBlock]
  @ObservationIgnored private(set) var layoutPreparation = MarkdownLayoutPreparation()

  public init(_ markdown: String) {
    self.markdown = markdown
    blocks = parseMarkdown(markdown)
  }
}

struct ParsedMarkdownBlock {
  let block: MarkdownBlock
  let runs: [MarkdownRun]
  let hasLeadingGap: Bool

  init(_ block: MarkdownBlock, hasLeadingGap: Bool = false) {
    self.block = block
    self.hasLeadingGap = hasLeadingGap
    switch block {
    case .paragraph(let text), .heading(_, let text), .listItem(_, let text, _), .quote(let text):
      runs = inlineRuns(text)
    case .code, .rule:
      runs = []
    }
  }
}

private func parseMarkdown(_ source: String) -> [ParsedMarkdownBlock] {
  let blocks = segmentMarkdown(source)
  return blocks.enumerated().map { index, block in
    let hasLeadingGap: Bool
    if index == 0 {
      hasLeadingGap = false
    } else if case .listItem = block, case .listItem = blocks[index - 1] {
      hasLeadingGap = false
    } else {
      hasLeadingGap = true
    }
    return ParsedMarkdownBlock(block, hasLeadingGap: hasLeadingGap)
  }
}
