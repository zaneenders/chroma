import Testing

@testable import Chroma

private struct NamedBlock: Block {

  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let context = context.component(Self.self)
    return buffer.customLeaf(
      context: context, focusRule: focusRule,
      expandsHorizontally: false, expandsVertically: false,
      measure: { sizeThatFits($0, context: context) },
      register: { register(in: $0, context: context) },
      paint: { paint(into: &$0, in: $1, context: context) })
  }

  @MainActor func register(in rect: Rect, context: BlockContext) {}

  let name: String

  var focusRule: FocusRule { .standard }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    Size(width: 10, height: 10)
  }

  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    drawList.text(name, at: rect.origin, color: .white)
  }
}

@MainActor
struct BoundaryTests {
  private func names(in tuple: TupleBlock) -> [String] {
    tuple.children.compactMap { ($0 as? NamedBlock)?.name }
  }

  @Test func builderFlattensConditionalsLoopsAndNestedTuplesInSourceOrder() {
    let flags = [true, false]
    let includeOptional = flags[0]
    let chooseFirst = flags[1]
    let rows = ["loop-0", "loop-1"]
    let nested = TupleBlock(children: [
      NamedBlock(name: "nested-0"),
      TupleBlock(children: [NamedBlock(name: "nested-1")]),
    ])

    let result = BlockBuilder.buildBlock(
      NamedBlock(name: "start"),
      BlockBuilder.buildOptional(includeOptional ? BlockBuilder.buildBlock(NamedBlock(name: "optional")) : nil),
      chooseFirst
        ? BlockBuilder.buildEither(first: BlockBuilder.buildBlock(NamedBlock(name: "first")))
        : BlockBuilder.buildEither(second: BlockBuilder.buildBlock(NamedBlock(name: "second"))),
      BlockBuilder.buildArray(rows.map { BlockBuilder.buildBlock(NamedBlock(name: $0)) }),
      nested
    )

    #expect(
      names(in: result) == [
        "start", "optional", "second", "loop-0", "loop-1", "nested-0", "nested-1",
      ])
    #expect(names(in: BlockBuilder.buildOptional(nil)).isEmpty)
    #expect(names(in: BlockBuilder.buildArray([])).isEmpty)
  }

  @Test func modifierOrderChangesBackgroundGeometryAndCommandOrder() {
    let context = BlockContext()
    let viewport = Rect(x: 0, y: 0, width: 40, height: 40)
    let red = Color(r: 1, g: 0, b: 0, a: 1)
    let blue = Color(r: 0, g: 0, b: 1, a: 1)

    var outerBackground = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(NamedBlock(name: "content").padding(5).background(red), context: context)
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &outerBackground, in: viewport)
    }
    #expect(
      outerBackground.paintSnapshot == [
        .fillRect(rect: viewport, color: red),
        .text(position: Point(x: 5, y: 5), text: "content", color: .white, scale: 1),
      ])

    var innerBackground = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(NamedBlock(name: "content").background(blue).padding(5), context: context)
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &innerBackground, in: viewport)
    }
    #expect(
      innerBackground.paintSnapshot == [
        .fillRect(rect: Rect(x: 5, y: 5, width: 30, height: 30), color: blue),
        .text(position: Point(x: 5, y: 5), text: "content", color: .white, scale: 1),
      ])
  }

  @Test func nestedClipModifiersProduceBalancedProperlyNestedCommands() {
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)
    let viewport = Rect(x: 0, y: 0, width: 20, height: 20)
    beginTestFrame(interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(NamedBlock(name: "x").clipped().clipped(), context: context)
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &list, in: viewport)
    }
    interaction.endFrame()

    #expect(
      list.paintSnapshot == [
        .pushClip(viewport), .pushClip(viewport),
        .text(position: .zero, text: "x", color: .white, scale: 1),
        .popClip, .popClip,
      ])
    #expect(interaction.clipStack.isEmpty)
  }

  @Test func widgetIDsAreStableDistinctAndRawValuesRemainExact() {
    #expect(WidgetID("stable") == WidgetID("stable"))
    #expect(WidgetID("stable").rawValue == 0x3f63_b56d_b289_0a16)
    #expect(WidgetID("é") != WidgetID("e\u{301}"), "IDs hash the exact UTF-8 spelling")
    #expect(WidgetID(rawValue: 42) == WidgetID(rawValue: 42))
    #expect(WidgetID(rawValue: 42) != WidgetID(rawValue: 43))
  }

  @Test func zeroAndNegativeProposalsStayFinite() {
    let context = BlockContext()
    let proposals = [
      Size.zero,
      Size(width: -100, height: -50),
    ]
    for proposal in proposals {
      let padded = measureBlock(
        NamedBlock(name: "x").padding(8), proposal: proposal, context: context)
      #expect(padded.width.isFinite && padded.height.isFinite)
      #expect(padded.width >= 0 && padded.height >= 0)

      let emptyStack = measureBlock(VStack {}, proposal: proposal, context: context)
      #expect(emptyStack == .zero)
    }
  }
}
