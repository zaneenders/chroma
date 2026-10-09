import Testing

@testable import Chroma

@MainActor
struct BoundaryTests {
  private func named(_ name: String, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    buffer.customLeaf(
      context: context, measure: { _ in Size(width: 10, height: 10) }, register: { _ in },
      paint: { list, rect in list.text(name, at: rect.origin, color: .white) })
  }

  @Test(arguments: [false, true], [false, true])
  func directConditionalsAndLoopsKeepExplicitSourceOrder(includeOptional: Bool, chooseFirst: Bool) {
    let rows = ["loop-0", "loop-1"]
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    var children = [named("start", into: &buffer, context: context.keyed("start"))]
    if includeOptional { children.append(named("optional", into: &buffer, context: context.keyed("optional"))) }
    let branch = chooseFirst ? "first" : "second"
    children.append(named(branch, into: &buffer, context: context.keyed(branch)))
    for row in rows { children.append(named(row, into: &buffer, context: context.keyed(row))) }
    for name in ["nested-0", "nested-1"] {
      children.append(named(name, into: &buffer, context: context.keyed(name)))
    }
    let root = buffer.stack(children, axis: .vertical, context: context)
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    context.interaction.beginFrame(input: InputState())
    buffer.register(root, in: rect)
    var list = DrawList()
    buffer.paint(root, into: &list, in: rect)
    context.interaction.endFrame()
    let names = list.paintSnapshot.compactMap { if case .text(_, let text, _, _) = $0 { text } else { nil } }
    var expected = ["start"]
    if includeOptional { expected.append("optional") }
    expected.append(chooseFirst ? "first" : "second")
    expected += ["loop-0", "loop-1", "nested-0", "nested-1"]
    #expect(names == expected)
    let empty = buffer.stack([], axis: .vertical, context: context.keyed("empty"))
    #expect(buffer.sizeThatFits(empty, rect.size) == .zero)
    context.interaction.beginFrame(input: InputState())
    buffer.register(empty, in: rect)
    var emptyList = DrawList()
    buffer.paint(empty, into: &emptyList, in: rect)
    context.interaction.endFrame()
    #expect(emptyList.commands.isEmpty)
  }

  @Test func modifierOrderChangesBackgroundGeometryAndCommandOrder() {
    let context = LayoutContext()
    let viewport = Rect(x: 0, y: 0, width: 40, height: 40)
    let red = Color(r: 1, g: 0, b: 0, a: 1)
    let blue = Color(r: 0, g: 0, b: 1, a: 1)

    var outerBackground = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.background(
        context: context,
        content: { buffer, context in
          let content = named("content", into: &buffer, context: context)
          return buffer.padding(content, 5, context: context)
        }, background: { $0.color(red, context: $1) })
      context.interaction.beginFrame(input: InputState())
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &outerBackground, in: viewport)
      context.interaction.endFrame()
    }
    #expect(
      outerBackground.paintSnapshot == [
        .fillRect(rect: viewport, color: red),
        .text(position: Point(x: 5, y: 5), text: "content", color: .white, scale: 1),
      ])

    var innerBackground = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let background = resolvedBuffer.background(
        context: context, content: { named("content", into: &$0, context: $1) },
        background: { $0.color(blue, context: $1) })
      let resolved = resolvedBuffer.padding(background, 5, context: context)
      context.interaction.beginFrame(input: InputState())
      resolvedBuffer.register(resolved, in: viewport)
      resolvedBuffer.paint(resolved, into: &innerBackground, in: viewport)
      context.interaction.endFrame()
    }
    #expect(
      innerBackground.paintSnapshot == [
        .fillRect(rect: Rect(x: 5, y: 5, width: 30, height: 30), color: blue),
        .text(position: Point(x: 5, y: 5), text: "content", color: .white, scale: 1),
      ])
  }

  @Test func nestedClipModifiersProduceBalancedProperlyNestedCommands() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    let viewport = Rect(x: 0, y: 0, width: 20, height: 20)
    beginTestFrame(interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let content = named("x", into: &resolvedBuffer, context: context)
      let inner = resolvedBuffer.clip(content, context: context)
      let resolved = resolvedBuffer.clip(inner, context: context)
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
    let context = LayoutContext()
    let proposals = [
      Size.zero,
      Size(width: -100, height: -50),
    ]
    for proposal in proposals {
      let padded = measureLayout(
        { buffer, context in
          let content = named("x", into: &buffer, context: context)
          return buffer.padding(content, 8, context: context)
        }, proposal: proposal, context: context)
      #expect(padded.width.isFinite && padded.height.isFinite)
      #expect(padded.width >= 0 && padded.height >= 0)

      let emptyStack = measureLayout(
        { $0.stack([], axis: .vertical, context: $1) }, proposal: proposal, context: context)
      #expect(emptyStack == .zero)
    }
  }
}
