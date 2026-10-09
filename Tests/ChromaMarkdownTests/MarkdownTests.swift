import ChromaTesting
import Testing

@testable import Chroma
@testable import ChromaMarkdown

struct MarkdownTests {
  @Test func parsesSupportedBlocks() {
    #expect(
      segmentMarkdown("# Heading\n\nText\n\n- one\n  - two\n2) three\n> quote\n---\n```swift\nlet x = 1\n```") == [
        .heading(level: 1, text: "Heading"), .paragraph("Text"),
        .listItem(marker: "•", text: "one", depth: 0),
        .listItem(marker: "•", text: "two", depth: 1),
        .listItem(marker: "2.", text: "three", depth: 0),
        .quote("quote"), .rule, .code(language: "swift", code: "let x = 1"),
      ])
  }

  @Test func incompleteStreamingInputRemainsVisible() {
    #expect(segmentMarkdown("```swift\nunfinished") == [.code(language: "swift", code: "unfinished")])
    #expect(inlineRuns("**unfinished `code") == [MarkdownRun(text: "**unfinished `code")])
    #expect(
      inlineRuns("**bold** and `**literal**`") == [
        MarkdownRun(text: "bold", bold: true), MarkdownRun(text: " and "),
        MarkdownRun(text: "**literal**", code: true),
      ])
  }

  @Test(arguments: [
    "| Name | Value |\n| --- | --- |",
    "| Name | Value |\n| --- | --- |\n| Apple | 1 |",
    "| Name | Value |\n| --- | --- |\n| | |",
  ])
  func tablesRemainSingleBlocks(source: String) throws {
    let blocks = segmentMarkdown(source)
    #expect(blocks.count == 1)
    let block = try #require(blocks.first)
    guard case .paragraph(let text) = block else {
      Issue.record("Expected a table to use the paragraph fallback")
      return
    }
    #expect(text.contains("Name"))
    #expect(text.contains("Value"))
    #expect(text.contains("|"))
    if source.contains("Apple") {
      #expect(text.contains("Apple"))
      #expect(text.contains("1"))
    }
  }

  @Test func streamingTablePrefixesCanBeLaidOut() {
    let source = "| Name | Value |\n| --- | --- |\n| Apple | 1 |"
    for length in 1...source.count {
      let blocks = segmentMarkdown(String(source.prefix(length)))
      let lines = layoutMarkdown(blocks, columns: 80, theme: .dark, baseColor: .white)
      #expect(!lines.isEmpty)
    }
  }

  @Test func tablesInsideListsRemainSingleBlocks() {
    let blocks = segmentMarkdown("- Item\n\n  | Name | Value |\n  | --- | --- |")
    #expect(blocks.count == 2)
    #expect(blocks.first == .listItem(marker: "•", text: "Item", depth: 0))
    guard case .paragraph(let text) = blocks.last else {
      Issue.record("Expected a nested table to use the paragraph fallback")
      return
    }
    #expect(text.contains("Name"))
    #expect(text.contains("Value"))
  }

  @Test func handlesCRLFAndPreservesTrailingCodeBlankLines() {
    #expect(segmentMarkdown("# Title\r\n\r\nBody") == [.heading(level: 1, text: "Title"), .paragraph("Body")])
    let lines = layoutMarkdown(segmentMarkdown("```\na\n\n```"), columns: 80, theme: .dark, baseColor: .white)
    #expect(lines.count == 2)
    #expect(lines.last?.kind == .code)
  }

  @Test func wrapsNarrowWidthsWithoutSplittingUnicodeCharacters() {
    let lines = layoutMarkdown(segmentMarkdown("café 👋 日本語"), columns: 1, theme: .dark, baseColor: .white)
    #expect(!lines.isEmpty)
    #expect(lines.allSatisfy { $0.columnCount <= 1 })
    #expect(lines.flatMap(\.runs).map(\.text).joined().contains("👋"))
  }

  @Test func fencedCodePreservesBlankLinesAndLiteralMarkup() {
    let lines = layoutMarkdown(segmentMarkdown("```\na\n\n**b**\n```"), columns: 80, theme: .dark, baseColor: .white)
    #expect(lines.count == 3)
    #expect(lines.allSatisfy { $0.kind == .code })
    #expect(lines[1].runs.map(\.text).joined().isEmpty)
    #expect(lines[2].runs.map(\.text).joined() == "**b**")
  }

  @Test func parsesCommonMarkBlocks() {
    #expect(
      segmentMarkdown("~~~~swift\n```literal\n~~~~") == [
        .code(language: "swift", code: "```literal")
      ])
    #expect(
      segmentMarkdown("````\na\n```\nb\n````") == [
        .code(language: nil, code: "a\n```\nb")
      ])
    #expect(segmentMarkdown("    **literal**") == [.code(language: nil, code: "**literal**")])
    #expect(
      segmentMarkdown("Title\n=====\n\n3. first\n   continuation\n   - nested\n4. second") == [
        .heading(level: 1, text: "Title"),
        .listItem(marker: "3.", text: "first\ncontinuation", depth: 0),
        .listItem(marker: "•", text: "nested", depth: 1),
        .listItem(marker: "4.", text: "second", depth: 0),
      ])
    let lines = layoutMarkdown(
      segmentMarkdown("> first\n> second\n>\n> third"),
      columns: 80, theme: .dark, baseColor: .white)
    #expect(lines.map { $0.runs.map(\.text).joined() }.joined(separator: "\n") == "| first\nsecond\n\nthird")
  }

  @Test func parsesEscapesEntitiesAndNestedFormatting() {
    #expect(
      inlineRuns(#"\*\*literal\*\* &amp; **bold *nested* `code`**"#) == [
        MarkdownRun(text: "**literal** & "),
        MarkdownRun(text: "bold nested ", bold: true),
        MarkdownRun(text: "code", code: true, bold: true),
      ])
    #expect(inlineRuns("``a ` b``") == [MarkdownRun(text: "a ` b", code: true)])
    #expect(inlineRuns("[label](https://example.com) ![alt](image.png)") == [MarkdownRun(text: "label alt")])
    #expect(inlineRuns("# literal") == [MarkdownRun(text: "# literal")])
    let lines = layoutMarkdown(
      segmentMarkdown(#"# **Title** &amp; \*literal\*"#),
      columns: 80, theme: .dark, baseColor: .white)
    #expect(lines.flatMap(\.runs).map(\.text).joined() == "# Title & *literal*")
  }

  @Test @MainActor func measurementUsesWidthAndContextScale() {
    let block = MarkdownLeaf(block: .paragraph("abcdefghij"), scale: 1, lineSpacing: 0)
    let context = BlockContext()
    let cell = context.fontMetrics.cellAdvance
    let height = context.fontMetrics.lineAdvance
    var buffer = LayoutBuffer()
    let root = buffer.emit(block, context: context)
    #expect(buffer.sizeThatFits(root, Size(width: cell * 2, height: 1000)).height == height * 5)
    let scaled = BlockContext(textScale: 2)
    let scaledRoot = buffer.emit(block, context: scaled)
    #expect(buffer.sizeThatFits(scaledRoot, Size(width: cell * 2, height: 1000)).height == height * 20)
    let empty = buffer.emit(MarkdownLeaf(block: .paragraph(""), scale: 1, lineSpacing: 0), context: context)
    #expect(buffer.sizeThatFits(empty, Size(width: 100, height: 100)).height == 0)
    var drawList = DrawList()
    buffer.paint(root, into: &drawList, in: Rect(x: 0, y: 0, width: 100, height: 100))
  }
}

@MainActor
struct MarkdownNavigationTests {
  @Test func eachSemanticBlockIsAStableNavigationLeaf() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let context = runtime.context
    let content = MarkdownText("# Heading\n\nParagraph\n\n- first\n- second\n\n```swift\nlet x = 1\n```")
    runtime.setContent(content)
    func render(_ commands: [Command] = []) {
      _ = runtime.render(
        viewport: Size(width: 500, height: 600), input: InputState(commands: commands), onChange: {})
    }
    func leaves(_ node: InteractionNode) -> [InteractionNode] {
      node.isLeaf ? [node] : node.children.flatMap(leaves)
    }
    render()
    let initial = leaves(context.interaction.tree!)
    #expect(initial.count == 5)
    let initialRects = initial.map(\.rect)
    context.interaction.focus(initial[0].leafID!)
    let first = context.interaction.selectedLeafID
    render([.navigation(.down)])
    #expect(context.interaction.selectedLeafID != first)
    render([.navigation(.up)])
    #expect(context.interaction.selectedLeafID == first)
    #expect(leaves(context.interaction.tree!).map(\.rect) == initialRects)
  }

  @Test func keyboardNavigationScrollsLaterBlocksIntoView() {
    let controller = ScrollViewController()
    let ui = NavigationTestHost(
      content: ScrollView(controller: controller) {
        MarkdownText((0..<30).map { "Paragraph \($0)" }.joined(separator: "\n\n"))
      }, size: Size(width: 300, height: 100))
    ui.press("j", "l")
    for _ in 0..<20 { ui.press("j") }
    #expect(controller.offset > 0)
    for _ in 0..<30 { ui.press("f") }
    #expect(controller.offset == 0)
  }
}

@MainActor
struct MarkdownSelectionTests {
  @Test func selectsRenderedCharactersCopiesAndRejectsEdits() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let context = runtime.context
    let target = FocusTarget()
    let content = MarkdownLeaf(block: .paragraph("**café** `👨‍👩‍👧‍👦` tea"), scale: 1, lineSpacing: 0)
      .focusTarget(target)
    runtime.setContent(content)
    func render(_ commands: [Command] = [], text: [TextEditEvent] = []) {
      _ = runtime.render(
        viewport: Size(width: 40, height: 300),
        input: InputState(commands: commands, textEvents: text), onChange: {})
    }
    render()
    target.focus()
    render()
    render([.navigation(.stepIn)])
    #expect(context.isSelectingText)
    render(text: [.selectCaretRight])
    #expect(context.interaction.copyText() == "c")
    render(text: [.selectAll])
    #expect(context.interaction.copyText() == "café 👨‍👩‍👧‍👦 tea")
    render(text: [.insert("oops"), .backspace, .deleteForward, .cut])
    #expect(context.interaction.copyText() == "café 👨‍👩‍👧‍👦 tea")
    render([.action(.cancel)])
    #expect(!context.isSelectingText)
    #expect(target.isFocused)
  }

  @Test func layoutOffsetsRespectSoftWrapsUnicodeAndExplicitNewlines() {
    let lines = layoutMarkdown(
      [.code(language: nil, code: "é👨‍👩‍👧‍👦abcd\n\nend")], columns: 3,
      theme: .dark, baseColor: .white)
    let layout = MarkdownLayout(
      lines: lines, lineHeight: 20, cellWidth: 10, scale: 1,
      rect: Rect(x: 0, y: 0, width: 30, height: 200))
    #expect(layout.text == "é👨‍👩‍👧‍👦abcd\n\nend")
    #expect(layout.position(at: 3).row == 1)
    #expect(layout.hitTest(Point(x: 10, y: 25)) == 4)
    #expect(layout.verticalOffset(1, direction: 1) == 4)
    #expect(layout.position(at: 8).row == 3)
  }
}

@MainActor
struct MarkdownDocumentSelectionTests {
  @Test func parentScopeCopiesMarkdownAndPlainTextInTreeOrder() {
    let context = BlockContext()
    let producer = FrameProducer()
    let content = Group("Session") {
      Text("Header").selectable()
      MarkdownText("**café**\n\n`code`")
      Text("Footer").selectable()
    }
    _ = producer.render(
      build: { buffer, context in buffer.emit(content, context: context) },
      viewport: Size(width: 500, height: 500),
      input: InputState(), context: context, onChange: {})
    context.interaction.navigationPath = []
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "Header\ncafé\ncode\nFooter")
    let entries = context.interaction.textLeafIDs(in: context.interaction.tree)
    #expect(entries.count == 4)
    #expect(entries.allSatisfy { context.interaction.documentRange(for: $0)?.isEmpty == false })
  }
}
