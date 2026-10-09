import Testing

@testable import Chroma
@testable import ChromaMarkdown

@MainActor
struct PreparedMarkdownLayoutTests {
  private let rect = Rect(x: 20, y: 30, width: 72, height: 200)
  private let leaf = MarkdownLeaf(block: .paragraph("**café** 👨‍👩‍👧‍👦 tea"), scale: 1, lineSpacing: 4)

  @Test func measurementRegistrationAndPaintingShareOneLayout() {
    let context = LayoutContext()
    let preparation = MarkdownLayoutPreparation()
    var buffer = LayoutBuffer()
    var current = leaf
    current.preparation = preparation
    let resolved = current.build(into: &buffer, context: context)
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let size = buffer.sizeThatFits(resolved, rect.size)
    #expect(size.height > 0)
    #expect(buffer.sizeThatFits(resolved, Size(width: rect.size.width, height: 999)) == size)
    #expect(preparation.layoutsBuilt == 1)
    context.interaction.beginFrame(input: InputState())
    buffer.register(resolved, in: rect)
    #expect(preparation.layoutsBuilt == 1)
    #expect(context.interaction.builderRoot?.children.count == 1)
    #expect(PipelineMetrics.snapshot.paints == 0)
    #expect(PipelineMetrics.snapshot.drawingCommands == 0)
    let handlers = context.interaction.building.inputHandlers.count
    var first = DrawList()
    buffer.paint(resolved, into: &first, in: rect)
    var second = DrawList()
    buffer.paint(resolved, into: &second, in: rect)
    #expect(preparation.layoutsBuilt == 1)
    #expect(first.commands == second.commands)
    #expect(context.interaction.builderRoot?.children.count == 1)
    #expect(context.interaction.building.inputHandlers.count == handlers)
    context.interaction.endFrame()
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "café 👨‍👩‍👧‍👦 tea")
  }

  @Test(
    arguments: [
      "# Heading\n\n**bold** and `code`\n\n- café 👨‍👩‍👧‍👦\n- 日本語\n\n> quote\n\n---",
      "```swift\nabcdefghij\n\n👨‍👩‍👧‍👦 café\n```",
      "| Name | Value |\n| --- | --- |\n| Apple | 1 |",
      "**unfinished `code",
    ], [Float(12), 72, 500])
  func preparedCommandsMatchUncachedLayout(source: String, width: Float) {
    let context = LayoutContext(textScale: 1.5)
    let bounds = Rect(x: 37, y: 41, width: width, height: 500)
    for block in segmentMarkdown(source) {
      let current = MarkdownLeaf(block: block, scale: 2, lineSpacing: 3, hasLeadingGap: true)
      var buffer = LayoutBuffer()
      let resolved = current.build(into: &buffer, context: context)
      let scale = current.scale * context.textScale
      let cellWidth = context.fontMetrics.cellAdvance * scale
      var lines = layoutMarkdown(
        [block], columns: max(1, Int(width / cellWidth)),
        theme: context.theme, baseColor: context.theme.foreground)
      lines.insert(VisualLine(), at: 0)
      let expected = MarkdownLayout(
        lines: lines, lineHeight: context.fontMetrics.lineAdvance * scale + current.lineSpacing,
        cellWidth: cellWidth, scale: scale, hasLeadingGap: true, rect: bounds)
      #expect(buffer.sizeThatFits(resolved, bounds.size).height == Float(lines.count) * expected.lineHeight)
      context.interaction.beginFrame(input: InputState())
      buffer.register(resolved, in: bounds)
      context.interaction.endFrame()
      var actualCommands = DrawList()
      buffer.paint(resolved, into: &actualCommands, in: bounds)
      var expectedCommands = DrawList()
      expected.draw(into: &expectedCommands, theme: context.theme, selection: context.textInputVisualState())
      #expect(actualCommands.commands == expectedCommands.commands)
    }
  }

  @Test func paintingCommittedLayoutDoesNotRegisterOrReplayInput() {
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    let resolved = leaf.build(into: &buffer, context: context)
    context.interaction.beginFrame(input: InputState())
    buffer.register(resolved, in: rect)
    context.interaction.endFrame()
    let leaves = context.interaction.tree?.children.map(\.leafID)
    let handlers = context.interaction.registrations.inputHandlers.count
    let buildingHandlers = context.interaction.building.inputHandlers.count
    let buildingActions = context.interaction.building.buttonActions.count
    var list = DrawList()
    buffer.paint(resolved, into: &list, in: rect)
    #expect(!list.commands.isEmpty)
    #expect(context.interaction.tree?.children.map(\.leafID) == leaves)
    #expect(context.interaction.registrations.inputHandlers.count == handlers)
    #expect(context.interaction.builderRoot == nil)
    #expect(context.interaction.building.inputHandlers.count == buildingHandlers)
    #expect(context.interaction.building.buttonActions.count == buildingActions)
    #expect(context.interaction.editingLeaf == nil)
  }

  @Test func changedInputsReplaceTheSingleEntry() {
    var context = LayoutContext()
    let preparation = MarkdownLayoutPreparation()
    var current = leaf
    var bounds = rect
    func resolve() -> MarkdownLayout { preparation.resolve(current, in: bounds, context: context) }
    let original = resolve()
    #expect(preparation.layoutsBuilt == 1)
    #expect(resolve().lines == original.lines)
    #expect(preparation.layoutsBuilt == 1)
    current = MarkdownLeaf(block: .paragraph("replacement"), scale: 1, lineSpacing: 4)
    #expect(resolve().text == "replacement")
    #expect(preparation.layoutsBuilt == 2)
    bounds.size.width = 24
    #expect(resolve().lines.count > original.lines.count)
    #expect(preparation.layoutsBuilt == 3)
    context.theme.foreground = .black
    #expect(resolve().lines.flatMap(\.runs).allSatisfy { $0.color == .black })
    #expect(preparation.layoutsBuilt == 4)
    context.textScale = 2
    #expect(resolve().cellWidth == 24)
    #expect(preparation.layoutsBuilt == 5)
    context.fontMetrics.lineAdvance = 50
    #expect(resolve().lineHeight == 104)
    #expect(preparation.layoutsBuilt == 6)
    context.fontMetrics.cellAdvance = 8
    #expect(resolve().cellWidth == 16)
    #expect(preparation.layoutsBuilt == 7)
    current = MarkdownLeaf(block: current.block, scale: 1, lineSpacing: 8)
    #expect(resolve().lineHeight == 108)
    #expect(preparation.layoutsBuilt == 8)
    current.hasLeadingGap = true
    #expect(resolve().lines.first == VisualLine())
    #expect(resolve().text == "replacement")
    #expect(preparation.layoutsBuilt == 9)
    current = leaf
    context = LayoutContext()
    bounds = rect
    #expect(resolve().lines == original.lines)
    #expect(preparation.layoutsBuilt == 10)  // Older keys are not retained.
  }

  @Test func originAndSameColumnWidthReuseShapingButRefreshGeometry() {
    let context = LayoutContext()
    let preparation = MarkdownLayoutPreparation()
    let original = preparation.resolve(leaf, in: rect, context: context)
    let moved = Rect(x: 140, y: 230, width: 73, height: 250)
    let changed = preparation.resolve(leaf, in: moved, context: context)
    #expect(preparation.layoutsBuilt == 1)
    #expect(changed.rect == moved)
    #expect(original.rect == rect)
    #expect(changed.hitTest(Point(x: 152, y: 231)) == 1)
    #expect(original.hitTest(Point(x: 32, y: 31)) == 1)
    #expect(changed.verticalOffset(1, direction: 1) == original.verticalOffset(1, direction: 1))
  }

  @Test func newOperationsInstallFreshTextAndGeometry() {
    let context = LayoutContext()
    func register(_ text: String, width: Float) {
      context.interaction.beginFrame(input: InputState())
      let content = MarkdownText(text)
      var buffer = LayoutBuffer()
      let resolved = content.build(into: &buffer, context: context)
      buffer.register(resolved, in: Rect(x: 20, y: 30, width: width, height: 400))
      context.interaction.endFrame()
      context.interaction.selectAll(at: .zero)
    }
    register("**first**", width: 200)
    #expect(context.interaction.copyText() == "first")
    register("**replacement café**", width: 24)
    #expect(context.interaction.copyText() == "replacement café")
    register("**first**", width: 200)
    #expect(context.interaction.copyText() == "first")
  }

  @Test func registrationRetainsSnapshotButNotPreparation() {
    let context = LayoutContext()
    weak var weakPreparation: MarkdownLayoutPreparation?
    context.interaction.beginFrame(input: InputState())
    do {
      let preparation = MarkdownLayoutPreparation()
      weakPreparation = preparation
      var buffer = LayoutBuffer()
      var current = leaf
      current.preparation = preparation
      let resolved = current.build(into: &buffer, context: context)
      buffer.register(resolved, in: rect)
      // Replacing the cache cannot change text captured by registered callbacks.
      _ = preparation.resolve(
        MarkdownLeaf(block: .paragraph("new value"), scale: 1, lineSpacing: 4),
        in: rect, context: context)
    }
    #expect(weakPreparation == nil)
    context.interaction.endFrame()
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "café 👨‍👩‍👧‍👦 tea")
  }

  @Test func emissionPreservesTheExistingLeafIdentity() {
    let context = LayoutContext()
    let expected = context.scoped([.component(ObjectIdentifier(MarkdownLeaf.self))]).widgetID
    context.interaction.beginFrame(input: InputState())
    var buffer = LayoutBuffer()
    let resolved = leaf.build(into: &buffer, context: context)
    buffer.register(resolved, in: rect)
    #expect(context.interaction.builderRoot?.children.map(\.leafID) == [expected])
    context.interaction.endFrame()
  }

  @Test(arguments: [false, true], [false, true])
  func focusHighlightPreservesPrimitiveBehavior(claimed: Bool, ignored: Bool) {
    var context = LayoutContext()
    context.focusLeafClaimed = claimed
    context.navigationIgnored = ignored
    var buffer = LayoutBuffer()
    let resolved = leaf.build(into: &buffer, context: context)
    context.interaction.beginFrame(input: InputState())
    buffer.register(resolved, in: rect)
    context.interaction.selectedLeafID = context.component(MarkdownLeaf.self).widgetID
    var list = DrawList()
    buffer.paint(resolved, into: &list, in: rect)
    var highlight = DrawList()
    highlight.strokeRect(rect, width: 2, color: context.theme.focus.ring)
    #expect(list.commands.contains(highlight.commands[0]) == (!claimed && !ignored))
    context.interaction.endFrame()
  }
}
