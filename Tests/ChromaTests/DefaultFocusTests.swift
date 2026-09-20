import Testing

@testable import Chroma

@MainActor
struct DefaultFocusTests {
  private let viewport = Rect(x: 0, y: 0, width: 100, height: 40)
  private let parked = InputState(pointerPosition: Point(x: 500, y: 500))
  private let context = RenderContext()

  private var standardHighlight: Color {
    HoverStyle.standardTint(in: context.theme)
  }

  @discardableResult
  private func render(_ content: any Block, input: InputState) -> DrawList {
    context.interaction.beginFrame(input: input)
    var list = DrawList()
    BlockEngine.draw(content, into: &list, in: viewport, context: context)
    context.interaction.endFrame()
    return list
  }

  private func leafRects() -> [Rect] {
    var rects: [Rect] = []
    func visit(_ node: FocusNode) {
      if node.isLeaf { rects.append(node.rect) }
      node.children.forEach(visit)
    }
    visit(context.interaction.tree ?? FocusNode(kind: .group, rect: .zero))
    return rects
  }

  private func highlightCommands(in list: DrawList, for highlighted: Rect) -> [DrawCommand] {
    list.commands.filter { command in
      if case .fillRect(let rect, let color) = command, rect == highlighted, color.a < 1 { return true }
      return false
    }
  }

  @Test func plainTextIsKeyboardReachable() {
    let content = VStack(spacing: 10) {
      Text("alpha")
      Text("beta")
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

  @Test func keyboardFocusAndPointerHoverDrawTheSameHighlight() {
    let content = VStack(spacing: 10) {
      Text("alpha")
      Text("beta")
    }

    render(content, input: parked)
    let target = leafRects().last!

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    let keyboard = render(content, input: parked)
    let focused = highlightCommands(in: keyboard, for: target)
    #expect(!focused.isEmpty, "keyboard focus highlights the text")

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.up)]))
    let hovered = render(
      content,
      input: InputState(pointerPosition: Point(x: target.minX + 1, y: target.minY + 1)))
    #expect(context.interaction.hoveredLeafID != nil)
    #expect(
      highlightCommands(in: hovered, for: target) == focused,
      "pointer hover shows the same UI state as keyboard focus")
  }

  @Test func pressingUsesThePressedTint() {
    let content = VStack(spacing: 10) {
      Text("alpha")
      Text("beta")
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
    #expect(list.commands.contains(.fillRect(rect: target, color: pressed)))
  }

  @Test func hoverStyleOverridesTheHighlight() {
    let tint = Color(r: 1, g: 0, b: 0, a: 0.25)
    let content = VStack(spacing: 10) {
      Text("alpha")
      Text("beta").hover(.tint(tint))
    }

    render(content, input: parked)
    let target = leafRects().last!
    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    let list = render(content, input: parked)
    #expect(list.commands.contains(.fillRect(rect: target, color: tint)))
    #expect(!list.commands.contains(.fillRect(rect: target, color: standardHighlight)))
  }

  @Test func hoverNoneRemovesDefaultFocusability() {
    let content = VStack(spacing: 10) {
      Text("alpha")
      Text("beta").hover(.none)
    }

    render(content, input: parked)
    let rects = leafRects()
    #expect(rects.count == 1, "decorative content registers no focus leaf")

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    #expect(leafRects() == rects, "navigation cannot reach the decorative text")
    #expect(context.interaction.tree?.node(at: context.interaction.selection ?? [])?.rect == rects.first)
  }

  @Test func controlsOwnTheirContent() {
    let content = VStack(spacing: 10) {
      Interactive(action: {}) { _ in Text("inside interactive") }
      Text("beside")
    }

    render(content, input: parked)
    #expect(leafRects().count == 2, "Interactive content registers no leaf of its own")
  }

  @Test func lazyRowsClaimTheirTextContent() {
    let controller = ScrollViewController()
    let content = LazyVStack(
      id: WidgetID("claim-list"), data: 0..<3, rowHeight: 20, spacing: 0,
      showsIndicator: false, controller: controller
    ) { index in
      VStack(spacing: 2) {
        Text("label \(index)")
        Text("value \(index)")
      }
    }

    render(content, input: parked)
    #expect(leafRects().count == 3, "each row is one focus stop, not one per text")

    render(content, input: InputState(pointerPosition: Point(x: 500, y: 500), commands: [.navigation(.down)]))
    let list = render(content, input: parked)
    #expect(!highlightCommands(in: list, for: leafRects()[1]).isEmpty, "the whole row highlights")
  }

  @Test func backgroundsStayDecorative() {
    let content = Text("foreground").background(Text("background"))

    render(content, input: parked)
    #expect(leafRects().count == 1)
    #expect(context.interaction.tree?.firstLeafPath() != nil)
  }

  /// A custom primitive that paints cells the way immediate-mode content does.
  private struct CellGrid: PrimitiveBlock {
    let action: (@MainActor () -> Void)?

    var focusRule: FocusRule { .container }

    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
      Size(width: proposal.width, height: 40)
    }

    func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
      context.withFocusGroup(in: rect, axis: .horizontal) {
        for column in 0..<2 {
          let box = Rect(
            x: rect.minX + Float(column) * 50, y: rect.minY, width: 50, height: 40)
          context.childScope(column).focusable(in: box, into: &drawList, action: action)
        }
      }
    }
  }

  @Test func focusableCellsPaintTheStandardHighlight() {
    let content = CellGrid(action: nil)

    render(content, input: parked)
    let rects = leafRects()
    #expect(rects == [Rect(x: 0, y: 0, width: 50, height: 40), Rect(x: 50, y: 0, width: 50, height: 40)])

    // Keyboard focus paints the standard tint over the first cell.
    let focused = render(content, input: parked)
    #expect(focused.commands.contains(.fillRect(rect: rects[0], color: standardHighlight)))

    // Pointer hover paints the same tint over the hovered cell.
    let hovered = render(content, input: InputState(pointerPosition: Point(x: 60, y: 10)))
    #expect(hovered.commands.contains(.fillRect(rect: rects[1], color: standardHighlight)))

    // Pressing uses the pressed tint.
    let list = render(
      content,
      input: InputState(pointerPosition: Point(x: 60, y: 10), pointerDown: true, pointerPressed: true))
    let pressed = HoverStyle.standardTint(in: context.theme, pressed: true)
    #expect(list.commands.contains(.fillRect(rect: rects[1], color: pressed)))
  }

  @Test func focusableCellsHonorHoverOverrides() {
    let tint = Color(r: 1, g: 0, b: 0, a: 0.25)
    let decorative = CellGrid(action: nil).hover(.none)
    let tinted = CellGrid(action: nil).hover(.tint(tint))

    render(decorative, input: parked)
    #expect(leafRects().isEmpty, "decorative cells register no focus leaf")

    render(tinted, input: parked)
    let list = render(tinted, input: parked)
    let first = leafRects()[0]
    #expect(list.commands.contains(.fillRect(rect: first, color: tint)))
    #expect(!list.commands.contains(.fillRect(rect: first, color: standardHighlight)))
  }

  @Test func focusableCellsActivateTheirAction() {
    var calls = 0
    let content = CellGrid { calls += 1 }

    render(content, input: parked)
    render(content, input: InputState(commands: [.action(.activate)]))
    #expect(calls == 1)
  }

  @Test func stacksOfOnlyDecorativeContentRegisterNoLeaf() {
    let content = VStack(spacing: 0) {
      Text("hidden").hover(.none)
      Spacer()
    }

    render(content, input: parked)
    #expect(leafRects().isEmpty, "a stack declares .container: its focus lives in its children")
  }
}
