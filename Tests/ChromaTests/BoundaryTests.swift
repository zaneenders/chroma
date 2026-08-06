import Testing
@testable import Chroma

private struct NamedBlock: PrimitiveBlock {
  let name: String

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Size(width: 10, height: 10)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.text(name, at: rect.origin, color: .white)
  }
}

@MainActor
struct BoundaryTests {
  private func names(in tuple: TupleBlock) -> [String] {
    BlockBuilder.flattenedChildren(tuple.children).compactMap { ($0 as? NamedBlock)?.name }
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

    #expect(names(in: result) == [
      "start", "optional", "second", "loop-0", "loop-1", "nested-0", "nested-1",
    ])
    #expect(names(in: BlockBuilder.buildOptional(nil)).isEmpty)
    #expect(names(in: BlockBuilder.buildArray([])).isEmpty)
  }

  @Test func modifierOrderChangesBackgroundGeometryAndCommandOrder() {
    let context = RenderContext()
    let viewport = Rect(x: 0, y: 0, width: 40, height: 40)
    let red = Color(r: 1, g: 0, b: 0, a: 1)
    let blue = Color(r: 0, g: 0, b: 1, a: 1)

    var outerBackground = DrawList()
    BlockEngine.draw(
      NamedBlock(name: "content").padding(5).background(red),
      into: &outerBackground, in: viewport, context: context)
    #expect(outerBackground.commands == [
      .fillRect(rect: viewport, color: red),
      .text(position: Point(x: 5, y: 5), text: "content", color: .white, scale: 1),
    ])

    var innerBackground = DrawList()
    BlockEngine.draw(
      NamedBlock(name: "content").background(blue).padding(5),
      into: &innerBackground, in: viewport, context: context)
    #expect(innerBackground.commands == [
      .fillRect(rect: Rect(x: 5, y: 5, width: 30, height: 30), color: blue),
      .text(position: Point(x: 5, y: 5), text: "content", color: .white, scale: 1),
    ])
  }

  @Test func nestedClipModifiersProduceBalancedProperlyNestedCommands() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let viewport = Rect(x: 0, y: 0, width: 20, height: 20)
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(NamedBlock(name: "x").clipped().clipped(), into: &list, in: viewport, context: context)
    interaction.endFrame()

    #expect(list.commands == [
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
    let context = RenderContext()
    let proposals = [
      Size.zero,
      Size(width: -100, height: -50),
    ]
    for proposal in proposals {
      let padded = BlockEngine.measure(
        NamedBlock(name: "x").padding(8), proposal: proposal, context: context)
      #expect(padded.width.isFinite && padded.height.isFinite)
      #expect(padded.width >= 0 && padded.height >= 0)

      let emptyStack = BlockEngine.measure(VStack {}, proposal: proposal, context: context)
      #expect(emptyStack == .zero)
    }
  }
}
