import Observation
import Synchronization
import Testing

@testable import Chroma
@testable import ChromaMarkdown

@MainActor
struct MarkdownDocumentTests {
  @Test func unchangedSourceAndBodyEvaluationsKeepTheRevision() {
    let document = MarkdownDocument("# Heading\n\n**first**")
    for _ in 0..<10 { _ = MarkdownText(document).body }
    document.markdown = "# Heading\n\n**first**"
    #expect(document.revision == 0)
    #expect(document.blocks.map(\.block) == [.heading(level: 1, text: "Heading"), .paragraph("**first**")])
    #expect(document.blocks[1].runs == [MarkdownRun(text: "first", bold: true)])
  }

  @Test func sourceMutationReplacesTheParseAndKeepsOldSnapshotsIntact() {
    let document = MarkdownDocument("**first**")
    let original = document.blocks
    document.markdown += "\n\n- second"
    #expect(document.revision == 1)
    #expect(document.blocks.count == 2)
    #expect(original.count == 1)
    #expect(original[0].runs == [MarkdownRun(text: "first", bold: true)])
    #expect(document.blocks[1].runs == [MarkdownRun(text: "second")])
    document.markdown = ""
    #expect(document.revision == 2)
    #expect(document.blocks.isEmpty)
    document.markdown = "**first**"
    #expect(document.revision == 3)
    #expect(document.blocks.map(\.block) == original.map(\.block))
  }

  @Test func revisionTracksExactSourceBytesIncludingUnicodeNormalization() {
    let document = MarkdownDocument("\u{e9}")
    document.markdown = "e\u{301}"
    #expect(document.revision == 1)
    #expect(Array(document.blocks[0].runs[0].text.utf8) == Array("e\u{301}".utf8))
  }

  @Test func documentMutationInvalidatesBodyObservation() {
    let document = MarkdownDocument("first")
    let changed = Mutex(false)
    withObservationTracking {
      _ = MarkdownText(document).body
    } onChange: {
      changed.withLock { $0 = true }
    }
    document.markdown = "second"
    #expect(changed.withLock { $0 })
  }

  @Test(arguments: [Float(12), 72, 500])
  func preparedInlineRunsMatchOrdinaryRendering(width: Float) {
    let source = "# **Heading**\n\n**café** and `code`\n\n- first\n- second\n\n> quote\n\n---\n\n```\n**literal**\n```"
    let document = MarkdownDocument(source)
    let columns = max(1, Int(width / 12))
    let blocks = document.blocks.map(\.block)
    #expect(
      layoutMarkdown(blocks, columns: columns, theme: .dark, baseColor: .white)
        == layoutMarkdown(
          blocks, columns: columns, theme: .dark, baseColor: .white,
          parsedRuns: document.blocks.map(\.runs)))
  }

  @Test func retainedRendererReadsCurrentDocumentAfterMutation() {
    let document = MarkdownDocument("**first**")
    let content = MarkdownText(document)
    let context = BlockContext()
    let producer = FrameProducer()
    func render() -> DrawList {
      let list = producer.render(
        content: content, viewport: Size(width: 120, height: 400),
        input: InputState(), context: context, onChange: {})
      context.interaction.selectAll(at: .zero)
      return list
    }
    let first = render()
    #expect(context.interaction.copyText() == "first")
    document.markdown = "**replacement café**\n\n`second`"
    let changed = render()
    #expect(context.interaction.copyText() == "replacement café\nsecond")
    #expect(changed.commands != first.commands)
    #expect(document.revision == 1)
  }

  @Test func documentMutationDoesNotChangeAnAlreadyPreparedOperation() {
    let document = MarkdownDocument("**first**")
    let content = MarkdownText(document)
    let context = BlockContext()
    let rect = Rect(x: 0, y: 0, width: 200, height: 100)
    var buffer = LayoutBuffer()
    let original = buffer.prepare(content, context: context)
    document.markdown = "**second**"
    context.interaction.beginFrame(input: InputState())
    buffer.register(original, in: rect)
    context.interaction.endFrame()
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "first")

    buffer.reset()
    let updated = buffer.prepare(content, context: context)
    context.interaction.beginFrame(input: InputState())
    buffer.register(updated, in: rect)
    context.interaction.endFrame()
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "second")
  }
}
