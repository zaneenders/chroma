import Testing

@testable import Chroma

@MainActor
struct DefaultFocusTests {
  private let viewport = Rect(x: 0, y: 0, width: 100, height: 40)
  private let parked = InputState(pointerPosition: Point(x: 500, y: 500))
  private let context = LayoutContext()

  private func focusBorder(_ rect: Rect) -> PaintSnapshotEntry {
    .strokeRect(rect: rect, width: 2, color: context.theme.focus.ring)
  }

  private var standardHighlight: Color {
    HoverStyle.standardTint(in: context.theme)
  }

  @discardableResult
  private func render(_ content: @escaping LayoutBuilder, input: InputState) -> DrawList {
    let isInitialFrame = context.interaction.tree == nil
    beginTestFrame(context.interaction, input: input)
    var list = DrawList()
    do {
      var buffer = LayoutBuffer()
      let root = content(&buffer, context)
      buffer.register(root, in: viewport)
      buffer.paint(root, into: &list, in: viewport)
    }
    context.interaction.endFrame()
    if isInitialFrame, context.interaction.selection == nil { context.interaction.focusFirstControlForTest() }
    return list
  }

  private func leafRects() -> [Rect] {
    var rects: [Rect] = []
    func visit(_ node: InteractionNode) {
      if node.isLeaf { rects.append(node.rect) }
      node.children.forEach(visit)
    }
    if let tree = context.interaction.tree { visit(tree) }
    return rects
  }

  private func highlightCommands(in list: DrawList, for highlighted: Rect) -> [PaintSnapshotEntry] {
    list.paintSnapshot.filter { command in
      if case .fillRect(let rect, let color) = command, rect == highlighted, color.a < 1 { return true }
      return false
    }
  }

  @Test func plainTextIsKeyboardReachable() {
    let content: LayoutBuilder = { buffer, context in
      let node15 = buffer.text(Text("alpha"), context: context.childScope(0))
      let node16 = buffer.text(Text("beta"), context: context.childScope(1))
      return buffer.stack([node15, node16], axis: .vertical, spacing: 10, context: context)
    }

    render(content, input: parked)
    let rects = leafRects()
    #expect(rects.count == 2, "each text registers one leaf; the stack registers none")
    #expect(context.interaction.selectedLeafID != nil)

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    #expect(leafRects() == rects, "leaf identity is stable across frames")
    let second = context.interaction.selection
    #expect(second != nil)
    #expect(context.interaction.tree?.node(at: second ?? [])?.rect == rects.last)
  }

  @Test func keyboardFocusUsesBorderWhilePointerHoverUsesTint() {
    let content: LayoutBuilder = { buffer, context in
      let node18 = buffer.text(Text("alpha"), context: context.childScope(0))
      let node19 = buffer.text(Text("beta"), context: context.childScope(1))
      return buffer.stack([node18, node19], axis: .vertical, spacing: 10, context: context)
    }

    render(content, input: parked)
    let target = leafRects().last!

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    let keyboard = render(content, input: parked)
    let focused = highlightCommands(in: keyboard, for: target)
    #expect(keyboard.paintSnapshot.contains(focusBorder(target)))
    #expect(focused.isEmpty)

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.up)]))
    let hovered = render(
      content,
      input: InputState(pointerPosition: Point(x: target.minX + 1, y: target.minY + 1)))
    #expect(context.interaction.hoveredLeafID != nil)
    #expect(hovered.paintSnapshot.contains(.fillRect(rect: target, color: standardHighlight)))
    #expect(!hovered.paintSnapshot.contains(focusBorder(target)))
  }

  @Test func pressingUsesThePressedTint() {
    let content: LayoutBuilder = { buffer, context in
      let node21 = buffer.text(Text("alpha"), context: context.childScope(0))
      let node22 = buffer.text(Text("beta"), context: context.childScope(1))
      return buffer.stack([node21, node22], axis: .vertical, spacing: 10, context: context)
    }

    render(content, input: parked)
    let target = leafRects().last!
    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    let list = render(
      content,
      input: InputState(
        pointerPosition: Point(x: target.minX + 1, y: target.minY + 1),
        pointerDown: true, pointerPressed: true))
    let pressed = HoverStyle.standardTint(in: context.theme, pressed: true)
    #expect(list.paintSnapshot.contains(.fillRect(rect: target, color: pressed)))
  }

  @Test func hoverStyleOverridesTheHighlight() {
    let tint = Color(r: 1, g: 0, b: 0, a: 0.25)
    let content: LayoutBuilder = { buffer, context in
      let node24 = buffer.text(Text("alpha"), context: context.childScope(0))
      var context25 = context.childScope(1)
      context25.hoverStyle = .tint(tint)
      let node26 = buffer.text(Text("beta"), context: context25)
      return buffer.stack([node24, node26], axis: .vertical, spacing: 10, context: context)
    }

    render(content, input: parked)
    let target = leafRects().last!
    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    let list = render(content, input: parked)
    #expect(list.paintSnapshot.contains(.fillRect(rect: target, color: tint)))
    #expect(!list.paintSnapshot.contains(.fillRect(rect: target, color: standardHighlight)))
  }

  @Test func navigationIgnoredRemovesDefaultFocusability() {
    let content: LayoutBuilder = { buffer, context in
      let node28 = buffer.text(Text("alpha"), context: context.childScope(0))
      var context29 = context.childScope(1)
      context29.navigationIgnored = true
      let node30 = buffer.text(Text("beta"), context: context29)
      return buffer.stack([node28, node30], axis: .vertical, spacing: 10, context: context)
    }

    render(content, input: parked)
    let rects = leafRects()
    #expect(rects.count == 1, "decorative content registers no focus leaf")

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    #expect(leafRects() == rects, "navigation cannot reach the decorative text")
    #expect(context.interaction.tree?.node(at: context.interaction.selection ?? [])?.rect == rects.first)
  }

  @Test func controlsOwnTheirContent() {
    let content: LayoutBuilder = { buffer, context in
      let node33 = buffer.interactive(
        action: {},
        content: { buffer, context, _ in
          return buffer.text(Text("inside interactive"), context: context)
        }, context: context.childScope(0))
      let node34 = buffer.text(Text("beside"), context: context.childScope(1))
      return buffer.stack([node33, node34], axis: .vertical, spacing: 10, context: context)
    }

    render(content, input: parked)
    #expect(leafRects().count == 2, "Interactive content registers no leaf of its own")
  }

  @Test func lazyRowsClaimTheirTextContent() {
    let controller = ScrollViewController()
    let content: LayoutBuilder = { buffer, context in
      let node39 = buffer.scrollView(
        ScrollView(
          data: 0..<3, rowHeight: 20, spacing: 0, showsIndicator: false, controller: controller,
          build: { buffer, context, index in
            let node36 = buffer.text(Text("label \(index)"), context: context.childScope(0))
            let node37 = buffer.text(Text("value \(index)"), context: context.childScope(1))
            return buffer.stack([node36, node37], axis: .vertical, spacing: 2, context: context)
          }), context: context.keyed(WidgetID("claim-list")))
      return node39
    }

    render(content, input: parked)
    #expect(leafRects().count == 3, "each row is one focus stop, not one per text")

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    let list = render(content, input: parked)
    #expect(list.paintSnapshot.contains(focusBorder(leafRects()[1])))
  }

  @Test func backgroundsStayDecorative() {
    let content: LayoutBuilder = { buffer, context in
      let node42 = buffer.background(
        context: context,
        content: { buffer, context in
          return buffer.text(Text("foreground"), context: context)
        },
        background: { buffer, context in
          return buffer.text(Text("background"), context: context)
        })
      return node42
    }

    render(content, input: parked)
    #expect(leafRects().count == 1)
    #expect(context.interaction.tree?.firstLeafPath() != nil)
  }

  @MainActor private struct CellGrid {

    func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        measure: { self.sizeThatFits($0, context: context) },
        register: { self.register(in: $0, context: context) },
        paint: { self.paint(into: &$0, in: $1, context: context) })
    }

    let action: (@MainActor () -> Void)?

    var focusRule: FocusRule { .container }

    @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size {
      Size(width: proposal.width, height: 40)
    }

    func register(in rect: Rect, context: LayoutContext) {
      context.withFocusGroup(in: rect, axis: .horizontal) {
        for column in 0..<2 {
          let box = Rect(
            x: rect.minX + Float(column) * 50, y: rect.minY, width: 50, height: 40)
          context.childScope(column).registerFocusable(in: box, action: action)
        }
      }
    }
    func paint(into list: inout DrawList, in rect: Rect, context: LayoutContext) {
      for column in 0..<2 {
        context.childScope(column).paintFocusHighlight(
          in: Rect(x: rect.minX + Float(column) * 50, y: rect.minY, width: 50, height: 40), into: &list)
      }
    }
  }

  @Test func focusableCellsPaintTheStandardHighlight() {
    let content: LayoutBuilder = { buffer, context in
      return CellGrid(action: nil).build(into: &buffer, context: context)
    }

    render(content, input: parked)
    let rects = leafRects()
    #expect(rects == [Rect(x: 0, y: 0, width: 50, height: 40), Rect(x: 50, y: 0, width: 50, height: 40)])

    let focused = render(content, input: parked)
    #expect(focused.paintSnapshot.contains(focusBorder(rects[0])))
    #expect(!focused.paintSnapshot.contains(.fillRect(rect: rects[0], color: standardHighlight)))

    let hovered = render(content, input: InputState(pointerPosition: Point(x: 60, y: 10)))
    #expect(hovered.paintSnapshot.contains(.fillRect(rect: rects[1], color: standardHighlight)))

    let list = render(
      content,
      input: InputState(pointerPosition: Point(x: 60, y: 10), pointerDown: true, pointerPressed: true))
    let pressed = HoverStyle.standardTint(in: context.theme, pressed: true)
    #expect(list.paintSnapshot.contains(.fillRect(rect: rects[1], color: pressed)))
  }

  @Test func focusableCellsHonorHoverOverrides() {
    let tint = Color(r: 1, g: 0, b: 0, a: 0.25)
    let decorative: LayoutBuilder = { buffer, context in
      var context44 = context
      context44.navigationIgnored = true
      return CellGrid(action: nil).build(into: &buffer, context: context44)
    }
    let tinted: LayoutBuilder = { buffer, context in
      var context46 = context
      context46.hoverStyle = .tint(tint)
      return CellGrid(action: nil).build(into: &buffer, context: context46)
    }

    render(decorative, input: parked)
    #expect(leafRects().isEmpty, "decorative cells register no focus leaf")

    render(tinted, input: parked)
    context.interaction.focusFirstControlForTest()
    let list = render(tinted, input: parked)
    let first = leafRects()[0]
    #expect(list.paintSnapshot.contains(.fillRect(rect: first, color: tint)))
    #expect(!list.paintSnapshot.contains(.fillRect(rect: first, color: standardHighlight)))
  }

  @Test func focusableCellsActivateTheirAction() {
    var calls = 0
    let content: LayoutBuilder = { buffer, context in
      return CellGrid { calls += 1 }.build(into: &buffer, context: context)
    }

    render(content, input: parked)
    render(content, input: InputState(commands: [.action(.activate)]))
    #expect(calls == 1)
  }

  @Test func stacksOfOnlyDecorativeContentRegisterNoLeaf() {
    let content: LayoutBuilder = { buffer, context in
      var context49 = context.childScope(0)
      context49.navigationIgnored = true
      let node50 = buffer.text(Text("hidden"), context: context49)
      let node51 = buffer.spacer(context: context.childScope(1))
      return buffer.stack([node50, node51], axis: .vertical, spacing: 0, context: context)
    }

    render(content, input: parked)
    #expect(leafRects().isEmpty, "a stack declares .container: its focus lives in its children")
  }
}
