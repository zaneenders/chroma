import Testing

@testable import Chroma
@testable import ChromaMarkdown

@MainActor
struct MarkdownWrapCacheTests {
  private let bounds = Rect(x: 20, y: 30, width: 72, height: 400)

  @Test func emissionAddsOnlyBlockLeavesAndOneStack() {
    let document = MarkdownDocument("# Heading\n\nParagraph\n\n- first\n- second")
    var buffer = LayoutBuffer()
    _ = MarkdownText(document).build(into: &buffer, context: LayoutContext())
    #expect(document.blocks.count == 4)
    #expect(buffer.count == document.blocks.count + 1)
  }

  @Test func repeatedOperationsReuseEveryDocumentBlock() {
    let document = MarkdownDocument("**first paragraph**\n\nsecond paragraph")
    let content = MarkdownText(document)
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    for _ in 0..<5 {
      buffer.reset()
      let node = content.build(into: &buffer, context: context)
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
    let context = LayoutContext()
    let cache = document.layoutPreparation
    func resolve(_ width: Float) {
      for index in document.blocks.indices {
        _ = cache.resolve(
          markdownLeaf(document, at: index), in: Rect(x: 0, y: 0, width: width, height: 500), context: context)
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
    let context = LayoutContext()
    let original = markdownLeaf(document)
    let oldCache = document.layoutPreparation
    #expect(oldCache.resolve(original, in: bounds, context: context).text == "first")
    document.markdown = "**replacement café**"
    #expect(document.blocks.count == 1)
    #expect(document.revision == 1)
    #expect(document.layoutPreparation !== oldCache)
    #expect(
      document.layoutPreparation.resolve(markdownLeaf(document), in: bounds, context: context).text
        == "replacement café")
    #expect(oldCache.resolve(original, in: bounds, context: context).text == "first")
    #expect(oldCache.layoutsBuilt == 1)
    #expect(document.layoutPreparation.layoutsBuilt == 1)
    let unchanged = document.layoutPreparation
    document.markdown = "**replacement café**"
    #expect(document.layoutPreparation === unchanged)
  }

  @Test func placementInputsReusePlansWhenColumnCountIsUnchanged() {
    let document = MarkdownDocument("**café** abcdefghij")
    let cache = document.layoutPreparation
    let current = markdownLeaf(document)
    var context = LayoutContext()
    let original = cache.resolve(current, in: bounds, context: context)
    context.fontMetrics.lineAdvance = 50
    #expect(cache.resolve(current, in: bounds, context: context).lineHeight == 54)
    context.fontMetrics.cellAdvance = 11
    #expect(cache.resolve(current, in: bounds, context: context).cellWidth == 11)
    context.textScale = 2
    let wider = Rect(x: 140, y: 230, width: 144, height: 500)
    let enlarged = cache.resolve(current, in: wider, context: context)
    #expect(enlarged.cellWidth == 22)
    #expect(enlarged.lineHeight == 104)
    let scaled = cache.resolve(
      markdownLeaf(document, scale: 2, lineSpacing: 8),
      in: Rect(x: 140, y: 230, width: 288, height: 500), context: context)
    #expect(scaled.cellWidth == 44)
    #expect(scaled.lineHeight == 208)
    #expect(scaled.lines == original.lines)
    #expect(scaled.plan.starts == original.plan.starts)
    #expect(scaled.text == original.text)
    #expect(cache.layoutsBuilt == 1)
    #expect(cache.cachedPlanCount == 1)
    #expect(original.rect == bounds)
    #expect(original.cellWidth == 12)
    #expect(original.hitTest(Point(x: 32, y: 31)) == 1)
    #expect(enlarged.hitTest(Point(x: 162, y: 231)) == 1)
    _ = cache.resolve(current, in: bounds, context: context)
    #expect(cache.layoutsBuilt == 2)  // Changing the column count still rewraps.
  }

  @Test(arguments: ["foreground", "accent", "positive", "warning"])
  func bakedTextColorsInvalidatePlans(color: String) {
    let document = MarkdownDocument("# heading\n\nplain `code`\n\n> quote\n\n- item")
    let cache = document.layoutPreparation
    var context = LayoutContext()
    let original = document.blocks.indices.map {
      cache.resolve(markdownLeaf(document, at: $0), in: bounds, context: context)
    }
    switch color {
    case "foreground": context.theme.foreground = .black
    case "accent": context.theme.accent = .black
    case "positive": context.theme.positive = .black
    default: context.theme.warning = .black
    }
    let changed = document.blocks.indices.map {
      cache.resolve(markdownLeaf(document, at: $0), in: bounds, context: context)
    }
    #expect(cache.layoutsBuilt == 2 * document.blocks.count)
    #expect(changed.flatMap(\.lines).flatMap(\.runs).contains { $0.color == .black })
    #expect(!original.flatMap(\.lines).flatMap(\.runs).contains { $0.color == .black })
    #expect(original.map(\.text) == changed.map(\.text))
    #expect(original.map { $0.plan.starts } == changed.map { $0.plan.starts })
  }

  @Test func paintingColorsRefreshWithoutInvalidatingPlans() {
    let document = MarkdownDocument("```\ncode\n```")
    let cache = document.layoutPreparation
    let current = markdownLeaf(document)
    var context = LayoutContext()
    let first = cache.resolve(current, in: bounds, context: context)
    context.theme.surface = .yellow
    context.theme.focus.selectionBackground = .black
    context.theme.focus.selectionForeground = .yellow
    context.theme.focus.ring = .black
    context.theme.button.cornerRadius = 42
    let changed = cache.resolve(current, in: bounds, context: context)
    #expect(cache.layoutsBuilt == 1)
    #expect(changed.lines == first.lines)
    var selected = DrawList()
    changed.draw(
      into: &selected, theme: context.theme,
      selection: TextInputState(hovered: false, held: false, editing: true, caretOffset: 2, selectionRange: 0..<2))
    var expectedSurface = DrawList()
    expectedSurface.fillRect(
      Rect(x: bounds.minX, y: bounds.minY, width: bounds.size.width, height: changed.lineHeight), color: .yellow)
    #expect(selected.commands.contains(expectedSurface.commands[0]))
    var expectedSelection = DrawList()
    expectedSelection.fillRect(
      Rect(x: bounds.minX, y: bounds.minY, width: 2 * changed.cellWidth, height: changed.lineHeight), color: .black)
    #expect(selected.commands.contains(expectedSelection.commands[0]))
    var expectedText = DrawList()
    expectedText.text("code", at: bounds.origin, color: .yellow, scale: 1)
    #expect(selected.commands.contains(expectedText.commands[0]))
    var caret = DrawList()
    changed.draw(
      into: &caret, theme: context.theme,
      selection: TextInputState(hovered: false, held: false, editing: true, caretOffset: 2))
    var expectedCaret = DrawList()
    expectedCaret.fillRect(
      Rect(x: bounds.minX + 2 * changed.cellWidth, y: bounds.minY, width: 1, height: changed.lineHeight), color: .black)
    #expect(caret.commands.contains(expectedCaret.commands[0]))
  }

  @Test func cachedTextAndOffsetsPreserveWrapsNewlinesAndLeadingGap() {
    let document = MarkdownDocument("Header\n\n```\né👨‍👩‍👧‍👦abcd\n\nend\n```")
    let cache = document.layoutPreparation
    let current = markdownLeaf(document, at: 1)
    let context = LayoutContext()
    let rect = Rect(x: 20, y: 30, width: 36, height: 400)
    let layout = cache.resolve(current, in: rect, context: context)
    #expect(layout.text == "é👨‍👩‍👧‍👦abcd\n\nend")
    #expect(layout.plan.starts == [0, 0, 3, 7, 8])
    #expect(layout.plan.characterCount == 11)
    #expect(layout.lines.first == VisualLine())
    #expect(layout.position(at: 0).row == 1)
    #expect(layout.position(at: 3).row == 2)
    #expect(layout.position(at: 8).row == 4)
    #expect(layout.hitTest(Point(x: 20, y: 31)) == 0)
    #expect(layout.hitTest(Point(x: 32, y: 30 + 2 * layout.lineHeight + 1)) == 4)
    #expect(layout.verticalOffset(1, direction: 1) == 4)
    #expect(layout.verticalOffset(1, direction: -1) == 0)
    #expect(layout.verticalOffset(11, direction: 1) == 11)
    // Eviction and other placements cannot alter a registered plan's value snapshot.
    for width: Float in [72, 120, 36] {
      _ = cache.resolve(current, in: Rect(x: 140, y: 230, width: width, height: 500), context: context)
    }
    #expect(cache.layoutsBuilt == 4)
    #expect(layout.plan.starts == [0, 0, 3, 7, 8])
    #expect(layout.rect == rect)
    #expect(layout.text == "é👨‍👩‍👧‍👦abcd\n\nend")
  }

  @Test func wrappedSpacesRemainCopiedCharacters() {
    let document = MarkdownDocument("abc def")
    let rect = Rect(x: 0, y: 0, width: 36, height: 100)
    let layout = document.layoutPreparation.resolve(markdownLeaf(document), in: rect, context: LayoutContext())
    #expect(layout.text == "abc def")
    #expect(layout.plan.starts == [0, 4])
    #expect(layout.position(at: 3).row == 0)
    #expect(layout.position(at: 4).row == 1)
    #expect(layout.verticalOffset(1, direction: 1) == 5)
  }

  @Test func reusedPlansAlwaysReturnCurrentPlacementAndHitTesting() {
    let document = MarkdownDocument("abcdefghij")
    let cache = document.layoutPreparation
    let current = markdownLeaf(document)
    let context = LayoutContext()
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
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    weak var cache: MarkdownLayoutPreparation?
    context.interaction.beginFrame(input: InputState())
    do {
      let document = MarkdownDocument("**retained text**")
      cache = document.layoutPreparation
      let node = MarkdownText(document).build(into: &buffer, context: context)
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
