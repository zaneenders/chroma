import Markdown

func segmentMarkdown(_ source: String) -> [MarkdownBlock] {
  var blocks: [MarkdownBlock] = []

  func append(_ node: any Markup, depth: Int = 0) {
    switch node {
    case let paragraph as Paragraph:
      blocks.append(.paragraph(inlineSource(paragraph)))
    case let heading as Heading:
      blocks.append(.heading(level: heading.level, text: inlineSource(heading)))
    case let code as CodeBlock:
      // cmark terminates every code block with a newline; it is not an extra visual line.
      let text = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
      blocks.append(.code(language: code.language, code: text))
    case is ThematicBreak:
      blocks.append(.rule)
    case let quote as BlockQuote:
      blocks.append(
        .quote(
          quote.children.map { child in
            child is Paragraph ? inlineSource(child) : child.detachedFromParent.format()
          }.joined(separator: "\n\n")))
    case is OrderedList, is UnorderedList:
      let start = (node as? OrderedList)?.startIndex
      for (index, item) in node.children.enumerated() {
        let marker = start.map { "\($0 + UInt(index))." } ?? "•"
        var firstParagraph = true
        for child in item.children {
          if let paragraph = child as? Paragraph {
            blocks.append(
              .listItem(
                marker: firstParagraph ? marker : "", text: inlineSource(paragraph), depth: depth))
            firstParagraph = false
          } else {
            append(child, depth: depth + 1)
          }
        }
      }
    case let table as Table:
      // Swift Markdown traps when formatting table heads, bodies, rows, or cells independently.
      blocks.append(.paragraph(table.detachedFromParent.format()))
    case let html as HTMLBlock:
      blocks.append(.paragraph(html.rawHTML))
    default:
      if node.childCount == 0 {
        blocks.append(.paragraph(node.format()))
      } else {
        for child in node.children { append(child, depth: depth) }
      }
    }
  }

  for child in Document(parsing: source).children { append(child) }
  return blocks
}

private func inlineSource(_ node: any Markup) -> String {
  func source(_ node: any Markup) -> String {
    switch node {
    case let text as Text:
      return text.string.map { character in
        "\\`*_{}[]<>()#+-.!&".contains(character) ? "\\" + String(character) : String(character)
      }.joined()
    case is SoftBreak:
      return "\n"
    case is LineBreak:
      return "  \n"
    case is Strong:
      return "**" + node.children.map(source).joined() + "**"
    case is Emphasis:
      return "*" + node.children.map(source).joined() + "*"
    default:
      return node.detachedFromParent.format()
    }
  }
  return node.children.map(source).joined()
}

func inlineRuns(_ text: String) -> [MarkdownRun] {
  guard !text.isEmpty else { return [] }
  var runs: [MarkdownRun] = []

  func appendText(_ text: String, code: Bool = false, bold: Bool = false) {
    guard !text.isEmpty else { return }
    if let last = runs.last, last.code == code, last.bold == bold {
      runs[runs.count - 1].text += text
    } else {
      runs.append(MarkdownRun(text: text, code: code, bold: bold))
    }
  }

  func append(_ node: any Markup, bold: Bool = false) {
    switch node {
    case let text as Text:
      appendText(text.string, bold: bold)
    case let code as InlineCode:
      appendText(code.code, code: true, bold: bold)
    case is SoftBreak, is LineBreak:
      appendText("\n", bold: bold)
    case let html as InlineHTML:
      appendText(html.rawHTML, bold: bold)
    default:
      for child in node.children { append(child, bold: bold || node is Strong) }
    }
  }

  // A plain-text prefix keeps leading inline syntax from being parsed as a block.
  let document = Document(parsing: "chroma-inline: " + text)
  for (index, child) in document.children.enumerated() {
    if index > 0 { appendText("\n\n") }
    append(child)
  }
  if let first = runs.first, first.text.hasPrefix("chroma-inline: ") {
    runs[0].text.removeFirst("chroma-inline: ".count)
    if runs[0].text.isEmpty { runs.removeFirst() }
  }
  return runs
}
