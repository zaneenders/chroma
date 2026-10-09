import Testing

@testable import Chroma

struct NavigationTreeTests {
  private let viewport = Rect(x: 0, y: 0, width: 200, height: 100)

  @discardableResult
  private func leaf(_ id: UInt64, in tree: InteractionTree, parent: InteractionNode) -> InteractionNode {
    tree.append(
      kind: .leaf(WidgetID(rawValue: id)), rect: Rect(x: 0, y: 0, width: 10, height: 10), parent: parent)
  }

  @Test func layoutGroupsFlattenButExplicitGroupsRemainAtomic() {
    let tree = InteractionTree()
    tree.reset()
    let layout = tree.append(kind: .group, rect: viewport, parent: tree.root)
    leaf(1, in: tree, parent: layout)
    let group = tree.append(kind: .group, rect: viewport, parent: layout, navigationID: WidgetID("panel"))
    let nested = leaf(2, in: tree, parent: group)

    let navigation = tree.navigationRoot(viewport: viewport)
    #expect(navigation.rect == viewport)
    #expect(navigation.children.count == 2)
    #expect(navigation.children[0].renderPath == [0, 0])
    #expect(navigation.children[1].renderPath == [0, 1])
    #expect(navigation.children[1].kind == .group)
    #expect(navigation.children[1].id == WidgetID("panel"))
    #expect(navigation.children[1].children[0].renderPath == [0, 1, 0])
    #expect(navigation.children[1].index == group.index)
    #expect(navigation.children[1].children[0].index == nested.index)
    #expect(tree.count == 5, "projecting navigation does not copy interaction rows")
  }

  @Test func emptyGroupsAndInvisibleLeavesDoNotBecomeNavigationTargets() {
    let tree = InteractionTree()
    tree.reset()
    tree.append(kind: .group, rect: viewport, parent: tree.root, navigationID: WidgetID("empty"))
    let hidden = tree.append(kind: .group, rect: viewport, parent: tree.root, navigationID: WidgetID("hidden"))
    tree.append(kind: .leaf(WidgetID(rawValue: 1)), rect: viewport, hitRect: .zero, parent: hidden)
    leaf(2, in: tree, parent: tree.root)

    let navigation = tree.navigationRoot(viewport: viewport)
    #expect(navigation.children.count == 1)
    #expect(navigation.children[0].kind == .leaf(WidgetID(rawValue: 2)))
  }

  @Test func hitTestingKeepsPainterOrderAndClippingIndependentOfNavigation() {
    let tree = InteractionTree()
    tree.reset()
    let back = tree.append(kind: .leaf(WidgetID("back")), rect: viewport, parent: tree.root)
    let group = tree.append(kind: .group, rect: viewport, parent: tree.root)
    let clipped = Rect(x: 20, y: 10, width: 10, height: 10)
    let front = tree.append(
      kind: .leaf(WidgetID("front")), rect: viewport, hitRect: clipped, parent: group,
      navigationIgnored: true)
    let navigation = tree.navigationRoot(viewport: viewport)

    #expect(navigation.children.count == 1)
    #expect(navigation.children.first?.index == back.index)
    let hit = tree.root.hitTest(Point(x: 25, y: 15))!
    #expect(hit == [1, 0])
    #expect(tree.root.node(at: hit)?.index == front.index)
    #expect(tree.root.node(at: hit)?.rect == viewport)
    #expect(tree.root.node(at: hit)?.hitRect == clipped)
    #expect(tree.root.hitTest(Point(x: 5, y: 5)) == [0])
  }

  @Test func revealableRowsRemainInNavigationOutsideTheClip() {
    let tree = InteractionTree()
    tree.reset()
    let group = tree.append(
      kind: .group, rect: viewport, parent: tree.root,
      scrollID: WidgetID("scroll"), navigationID: WidgetID("scroll"), canBeRevealed: true)
    let row = tree.append(
      kind: .leaf(WidgetID("offscreen")), rect: Rect(x: 0, y: 200, width: 20, height: 10),
      hitRect: .zero, parent: group, canBeRevealed: true)
    let navigation = tree.navigationRoot(viewport: viewport)
    #expect(navigation.path(to: row.leafID!) == [0, 0])
    #expect(navigation.node(at: [0, 0])?.index == row.index)
    #expect(tree.root.hitTest(Point(x: 5, y: 205)) == nil)
  }

  @Test func resetReusesStorageWithoutKeepingPreviousLinks() {
    let tree = InteractionTree()
    tree.reset()
    for index in 0..<100 { leaf(UInt64(index), in: tree, parent: tree.root) }
    _ = tree.navigationRoot(viewport: viewport)
    let capacity = tree.capacity
    tree.reset()
    leaf(200, in: tree, parent: tree.root)
    let navigation = tree.navigationRoot(viewport: viewport)
    #expect(tree.capacity == capacity)
    #expect(tree.count == 2)
    #expect(tree.root.children.count == 1)
    #expect(navigation.children.count == 1)
    #expect(navigation.path(to: WidgetID(rawValue: 0)) == nil)
    #expect(navigation.path(to: WidgetID(rawValue: 200)) == [0])
  }
}

@MainActor
struct GroupRegistrationTests {
  @Test func rootStartsUnselectedAndGroupsRequireEntry() {
    let context = BlockContext()
    let producer = FrameProducer()
    let first = FocusTarget()
    let inside = FocusTarget()
    let content = VStack {
      Button("First") {}.focusTarget(first)
      Group { Button("Inside") {}.focusTarget(inside) }
    }

    func render(_ commands: [Command] = []) {
      _ = producer.render(
        build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 200, height: 100),
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
    let context = BlockContext()
    let producer = FrameProducer()
    let target = FocusTarget()
    let content = HStack {
      Group { Button("Target") {}.focusTarget(target) }
      Button("Outside") {}
    }

    _ = producer.render(
      build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 200, height: 100),
      input: InputState(),
      context: context, onChange: {})
    let path = context.interaction.tree!.findLeaf(target.boundID!)!
    let rect = context.interaction.tree!.node(at: path)!.rect
    _ = producer.render(
      build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 200, height: 100),
      input: InputState(
        pointerPosition: Point(x: rect.minX + 1, y: rect.minY + 1), pointerDown: true,
        pointerPressed: true), context: context, onChange: {})

    #expect(target.isFocused)
    #expect(context.interaction.navigationPath.count == 2)
  }

  @Test func groupRegistersOneBoundaryWithoutChangingLeafPaths() {
    let context = BlockContext()
    let producer = FrameProducer()
    let content = VStack {
      Button("Before") {}
      Group {
        Button("Inside") {}
      }
    }

    _ = producer.render(
      build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 200, height: 100),
      input: InputState(), context: context, onChange: {})

    let navigation = context.interaction.navigation!
    #expect(navigation.children.count == 2)
    #expect(navigation.children[1].children.count == 1)
    #expect(context.interaction.tree?.node(at: navigation.children[1].children[0].renderPath)?.isLeaf == true)
  }
}

@MainActor
struct InteractionStorageTests {
  @Test func commitSwapsReusableRowsAndReconcilesEditingByKey() {
    let interaction = Interaction()
    let rect = Rect(x: 0, y: 0, width: 80, height: 20)
    let first = WidgetID("first")
    let second = WidgetID("second")
    func register(_ ids: [WidgetID]) {
      interaction.beginGroup(rect: rect)
      for id in ids { interaction.registerLeaf(id: id, rect: rect) }
      interaction.endGroup()
    }

    interaction.beginFrame(input: InputState())
    register([first, second])
    interaction.endFrame()
    interaction.focus(second, editing: true)
    let committed = interaction.tree!
    let storage = committed.storage
    let capacity = storage.capacity
    #expect(interaction.selection == [0, 1])

    interaction.beginFrame(input: InputState())
    register([second, first])
    #expect(interaction.tree == committed, "registration leaves committed geometry intact")
    #expect(committed.findLeaf(second) == [0, 1])
    interaction.endFrame()
    #expect(interaction.tree?.storage !== storage)
    #expect(interaction.selection == [0, 0])
    #expect(interaction.editingLeaf == second)
    #expect(interaction.isTextEditing)

    interaction.beginFrame(input: InputState())
    register([first])
    interaction.endFrame()
    #expect(interaction.tree?.storage === storage)
    #expect(storage.capacity == capacity)
    #expect(interaction.selectedLeafID == first)
    #expect(interaction.editingLeaf == nil)
    #expect(!interaction.isTextEditing)
    #expect(interaction.tree?.findLeaf(second) == nil)
  }
}
