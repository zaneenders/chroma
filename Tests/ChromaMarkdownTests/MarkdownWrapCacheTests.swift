import Testing

@testable import Chroma
@testable import ChromaMarkdown

@MainActor
struct MarkdownWrapCacheTests {
  private let bounds = Rect(x: 20, y: 30, width: 72, height: 400)

  private func leaf(_ document: MarkdownDocument, at index: Int = 0) -> MarkdownLeaf {
    MarkdownLeaf(
      block: document.blocks[index].block, scale: 1, lineSpacing: 4,
      hasLeadingGap: index > 0, parsedRuns: document.blocks[index].runs,
      preparation: document.layoutPreparation, source: (document.revision, index))
  }

  @Test func repeatedOperationsReuseEveryDocumentBlock() {
    let document = MarkdownDocument("**first paragraph**\n\nsecond paragraph")
    let content = MarkdownText(document)
    let context = BlockContext()
    var buffer = LayoutBuffer()
    for _ in 0..<5 {
      buffer.reset()
      let node = buffer.emit(content, context: context)
      _ = buffer.sizeThatFits(node, bounds.size)
      context.interaction.beginFrame(input: InputState())
      buffer.register(node, in: bounds)
      var list = DrawList()
      buffer.paint(node, into: &list, in: bounds)
      context.interaction.endFrame()
    }
    #expect(document.layoutPreparation.layoutsBuilt == 2)
    #expect(document.layoutPreparation.cachedPlanCount == 1)
    #expect(document.layoutPreparation.cachedBlockCount == 2)
  }

  @Test func twoWidthSlotsAreReusedAndOldestSlotIsEvicted() {
    let document = MarkdownDocument("first paragraph\n\nsecond paragraph")
    let context = BlockContext()
    let cache = document.layoutPreparation
    func resolve(_ width: Float) {
      for index in document.blocks.indices {
        _ = cache.resolve(leaf(document, at: index), in: Rect(x: 0, y: 0, width: width, height: 500), context: context)
      }
    }
    resolve(72)
    resolve(120)
    #expect(cache.layoutsBuilt == 4)
    resolve(120)
    resolve(72)
    #expect(cache.layoutsBuilt == 4)
    resolve(24)
    #expect(cache.layoutsBuilt == 6)
    #expect(cache.cachedPlanCount == 2)
    #expect(cache.cachedBlockCount == 4)
    resolve(72)
    #expect(cache.layoutsBuilt == 8)
    #expect(cache.cachedPlanCount == 2)
    #expect(cache.cachedBlockCount == 4)
  }

  @Test func sameCountStreamingReplacesPlansAndPreservesOldOperations() {
    let document = MarkdownDocument("**first**")
    let context = BlockContext()
    let original = leaf(document)
    let oldCache = document.layoutPreparation
    #expect(oldCache.resolve(original, in: bounds, context: context).text == "first")
    document.markdown = "**replacement café**"
    #expect(document.blocks.count == 1)
    #expect(document.revision == 1)
    #expect(document.layoutPreparation !== oldCache)
    #expect(document.layoutPreparation.resolve(leaf(document), in: bounds, context: context).text == "replacement café")
    #expect(oldCache.resolve(original, in: bounds, context: context).text == "first")
    #expect(oldCache.layoutsBuilt == 1)
    #expect(document.layoutPreparation.layoutsBuilt == 1)
    let unchanged = document.layoutPreparation
    document.markdown = "**replacement café**"
    #expect(document.layoutPreparation === unchanged)
  }

  @Test func revisionParticipatesInWrapPlanLookup() {
    let document = MarkdownDocument("first")
    let cache = document.layoutPreparation
    let context = BlockContext()
    _ = cache.resolve(leaf(document), in: bounds, context: context)
    let updated = MarkdownLeaf(
      block: .paragraph("second"), scale: 1, lineSpacing: 4,
      parsedRuns: [MarkdownRun(text: "second")], preparation: cache, source: (1, 0))
    #expect(cache.resolve(updated, in: bounds, context: context).text == "second")
    #expect(cache.layoutsBuilt == 2)
  }

  @Test func styleAndMetricChangesRebuildPlans() {
    let document = MarkdownDocument("**café** abcdefghij")
    let cache = document.layoutPreparation
    var current = leaf(document)
    var context = BlockContext()
    _ = cache.resolve(current, in: bounds, context: context)
    context.theme.foreground = .black
    let recolored = cache.resolve(current, in: bounds, context: context)
    #expect(recolored.lines.flatMap(\.runs).allSatisfy { $0.color == .black })
    context.fontMetrics.lineAdvance = 50
    #expect(cache.resolve(current, in: bounds, context: context).lineHeight == 54)
    context.fontMetrics.cellAdvance = 8
    #expect(cache.resolve(current, in: bounds, context: context).cellWidth == 8)
    context.textScale = 2
    #expect(cache.resolve(current, in: bounds, context: context).cellWidth == 16)
    current = MarkdownLeaf(
      block: current.block, scale: 2, lineSpacing: 8,
      parsedRuns: current.parsedRuns, preparation: cache, source: current.source)
    let scaled = cache.resolve(current, in: bounds, context: context)
    #expect(scaled.lineHeight == 208)
    #expect(scaled.cellWidth == 32)
    #expect(cache.layoutsBuilt == 6)
    #expect(cache.cachedPlanCount == 2)
  }

  @Test func reusedPlansAlwaysReturnCurrentPlacementAndHitTesting() {
    let document = MarkdownDocument("abcdefghij")
    let cache = document.layoutPreparation
    let current = leaf(document)
    let context = BlockContext()
    let first = cache.resolve(current, in: bounds, context: context)
    let moved = Rect(x: 140, y: 230, width: 73, height: 500)
    let second = cache.resolve(current, in: moved, context: context)
    #expect(cache.layoutsBuilt == 1)
    #expect(first.rect == bounds)
    #expect(second.rect == moved)
    #expect(first.hitTest(Point(x: 32, y: 31)) == 1)
    #expect(second.hitTest(Point(x: 152, y: 231)) == 1)
  }

  @Test func droppingDocumentAndOperationReleasesPlansButKeepsRegisteredTextSnapshot() {
    let context = BlockContext()
    var buffer = LayoutBuffer()
    weak var cache: MarkdownLayoutPreparation?
    context.interaction.beginFrame(input: InputState())
    do {
      let document = MarkdownDocument("**retained text**")
      cache = document.layoutPreparation
      let node = buffer.emit(MarkdownText(document), context: context)
      buffer.register(node, in: bounds)
    }
    #expect(cache != nil)
    buffer.reset()
    #expect(cache == nil)
    context.interaction.endFrame()
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "retained text")
  }
}
