import Testing

@testable import Chroma

struct NavigationTreeTests {
  private let viewport = Rect(x: 0, y: 0, width: 200, height: 100)

  private func leaf(_ id: UInt64) -> FocusNode {
    FocusNode(kind: .leaf(WidgetID(rawValue: id)), rect: Rect(x: 0, y: 0, width: 10, height: 10))
  }

  @Test func layoutGroupsFlattenButExplicitGroupsRemainAtomic() {
    let root = FocusNode(kind: .group, rect: .zero)
    let layout = FocusNode(kind: .group, rect: viewport, axis: .vertical)
    let group = FocusNode(kind: .group, rect: viewport, navigationID: WidgetID("panel"))
    group.children = [leaf(2)]
    layout.children = [leaf(1), group]
    root.children = [layout]

    let navigation = NavigationNode(root: root, viewport: viewport)
    #expect(navigation.rect == viewport)
    #expect(navigation.children.count == 2)
    #expect(navigation.children[0].renderPath == [0, 0])
    #expect(navigation.children[1].renderPath == [0, 1])
    #expect(navigation.children[1].kind == .group(WidgetID("panel")))
    #expect(navigation.children[1].children[0].renderPath == [0, 1, 0])
  }

  @Test func emptyGroupsAndInvisibleLeavesDoNotBecomeNavigationTargets() {
    let root = FocusNode(kind: .group, rect: .zero)
    let empty = FocusNode(kind: .group, rect: viewport, navigationID: WidgetID("empty"))
    let invisible = FocusNode(kind: .leaf(WidgetID(rawValue: 1)), rect: viewport, hitRect: .zero)
    let hidden = FocusNode(kind: .group, rect: viewport, navigationID: WidgetID("hidden"))
    hidden.children = [invisible]
    root.children = [empty, hidden, leaf(2)]

    let navigation = NavigationNode(root: root, viewport: viewport)
    #expect(navigation.children.count == 1)
    #expect(navigation.children[0].kind == .leaf(WidgetID(rawValue: 2)))
  }
}

@MainActor
struct GroupRegistrationTests {
  @Test func rootStartsUnselectedAndGroupsRequireEntry() {
    let context = RenderContext()
    let producer = FrameProducer()
    let first = FocusTarget()
    let inside = FocusTarget()
    let content = VStack {
      Button("First") {}.focusTarget(first)
      Group { Button("Inside") {}.focusTarget(inside) }
    }

    func render(_ commands: [Command] = []) {
      _ = producer.render(
        content: content, viewport: Size(width: 200, height: 100),
        input: InputState(commands: commands), context: context, onChange: {})
    }
    render()
    #expect(context.interaction.navigationPath.isEmpty)
    #expect(!first.isFocused && !inside.isFocused)
    render([.navigation(.down)])
    #expect(first.isFocused)
    render([.navigation(.down)])
    #expect(context.interaction.selection == nil)
    render([.action(.activate)])
    #expect(!inside.isFocused)
    render([.navigation(.stepIn)])
    #expect(inside.isFocused)
    render([.navigation(.stepOut)])
    #expect(context.interaction.selection == nil)
    #expect(context.interaction.navigationPath.count == 1)
  }

  @Test func clickingInsideAGroupEntersItsAncestorChain() {
    let context = RenderContext()
    let producer = FrameProducer()
    let target = FocusTarget()
    let content = HStack {
      Group { Button("Target") {}.focusTarget(target) }
      Button("Outside") {}
    }

    _ = producer.render(
      content: content, viewport: Size(width: 200, height: 100), input: InputState(),
      context: context, onChange: {})
    let path = context.interaction.tree!.findLeaf(target.boundID!)!
    let rect = context.interaction.tree!.node(at: path)!.rect
    _ = producer.render(
      content: content, viewport: Size(width: 200, height: 100),
      input: InputState(
        pointerPosition: Point(x: rect.minX + 1, y: rect.minY + 1), pointerDown: true,
        pointerPressed: true), context: context, onChange: {})

    #expect(target.isFocused)
    #expect(context.interaction.navigationPath.count == 2)
  }

  @Test func groupRegistersOneBoundaryWithoutChangingLeafPaths() {
    let context = RenderContext()
    let producer = FrameProducer()
    let content = VStack {
      Button("Before") {}
      Group {
        Button("Inside") {}
      }
    }

    _ = producer.render(
      content: content, viewport: Size(width: 200, height: 100),
      input: InputState(), context: context, onChange: {})

    let navigation = NavigationNode(
      root: context.interaction.tree!, viewport: Rect(x: 0, y: 0, width: 200, height: 100))
    #expect(navigation.children.count == 2)
    #expect(navigation.children[1].children.count == 1)
    #expect(context.interaction.tree?.node(at: navigation.children[1].children[0].renderPath)?.isLeaf == true)
  }
}
