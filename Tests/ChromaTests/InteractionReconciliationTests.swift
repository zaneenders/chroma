import Observation
import Synchronization
import Testing

@testable import Chroma

struct InteractionLookupRegressionTests {
  private let rect = Rect(x: 0, y: 0, width: 80, height: 20)

  @Test func navigationLookupIncludesOnlyProjectedAncestry() {
    let tree = InteractionTree()
    tree.reset()
    let groupID = WidgetID("panel")
    let group = tree.append(kind: .group, rect: rect, parent: tree.root, navigationID: groupID)
    let visible = tree.append(kind: .leaf(WidgetID("visible")), rect: rect, parent: group)
    let ignored = tree.append(
      kind: .leaf(WidgetID("ignored")), rect: rect, parent: tree.root, navigationIgnored: true)
    let invisible = tree.append(
      kind: .leaf(WidgetID("invisible")), rect: rect, hitRect: .zero, parent: tree.root)
    let hiddenGroup = tree.append(
      kind: .group, rect: rect, parent: tree.root, navigationID: WidgetID("hidden panel"),
      navigationIgnored: true)
    let hiddenDescendant = tree.append(
      kind: .leaf(WidgetID("hidden descendant")), rect: rect, parent: hiddenGroup)
    let navigation = tree.navigationRoot(viewport: rect)

    #expect(navigation.path(to: groupID).flatMap { navigation.node(at: $0)?.index } == group.index)
    #expect(navigation.path(to: visible.leafID!).flatMap { navigation.node(at: $0)?.index } == visible.index)
    for excluded in [ignored, invisible, hiddenDescendant] {
      #expect(tree.root.findLeaf(excluded.leafID!) == excluded.renderPath)
      #expect(navigation.path(to: excluded.leafID!) == nil)
    }
    #expect(hiddenDescendant.acceptsFocus, "navigation lookup must check ancestors, not just the leaf")
    #expect(navigation.path(to: WidgetID("hidden panel")) == nil)
  }

  @Test func sharedGroupAndLeafIDsRetainProjectedPreorderPrecedence() {
    let tree = InteractionTree()
    tree.reset()
    let leafFirstID = WidgetID("leaf first")
    let firstLeaf = tree.append(kind: .leaf(leafFirstID), rect: rect, parent: tree.root)
    let laterGroup = tree.append(
      kind: .group, rect: rect, parent: tree.root, navigationID: leafFirstID)
    tree.append(kind: .leaf(WidgetID("child one")), rect: rect, parent: laterGroup)
    let groupFirstID = WidgetID("group first")
    let firstGroup = tree.append(
      kind: .group, rect: rect, parent: tree.root, navigationID: groupFirstID)
    tree.append(kind: .leaf(groupFirstID), rect: rect, parent: firstGroup)
    let ignoredID = WidgetID("ignored first")
    tree.append(kind: .leaf(ignoredID), rect: rect, parent: tree.root, navigationIgnored: true)
    let projectedGroup = tree.append(
      kind: .group, rect: rect, parent: tree.root, navigationID: ignoredID)
    tree.append(kind: .leaf(WidgetID("child two")), rect: rect, parent: projectedGroup)
    let navigation = tree.navigationRoot(viewport: rect)

    #expect(navigation.path(to: leafFirstID).flatMap { navigation.node(at: $0)?.index } == firstLeaf.index)
    #expect(navigation.path(to: groupFirstID).flatMap { navigation.node(at: $0)?.index } == firstGroup.index)
    #expect(navigation.path(to: ignoredID).flatMap { navigation.node(at: $0)?.index } == projectedGroup.index)
  }

}

@MainActor
struct InteractionReconciliationTests {
  private let rect = Rect(x: 0, y: 0, width: 80, height: 20)

  @Test func unselectedWindowUsesCommonRenderAncestorOfFlattenedNavigationItems() {
    let interaction = Interaction()
    let command = Command.application("test")
    var calls: [String] = []
    interaction.beginFrame(input: InputState())
    interaction.building.commandHandlers.append(
      .init(
        path: [], command: command,
        action: {
          calls.append("root")
          return .handled
        }))
    interaction.beginGroup(rect: rect)
    let common = interaction.builderPath
    interaction.building.commandHandlers.append(
      .init(
        path: common, command: command,
        action: {
          calls.append("common")
          return .ignored
        }))
    interaction.beginGroup(rect: rect)
    interaction.building.commandHandlers.append(
      .init(
        path: interaction.builderPath, command: command,
        action: {
          calls.append("left")
          return .handled
        }))
    interaction.registerLeaf(id: WidgetID("left"), rect: rect)
    interaction.endGroup()
    interaction.beginGroup(rect: rect)
    interaction.building.commandHandlers.append(
      .init(
        path: interaction.builderPath, command: command,
        action: {
          calls.append("right")
          return .handled
        }))
    interaction.registerLeaf(id: WidgetID("right"), rect: rect)
    interaction.endGroup()
    interaction.endGroup()
    interaction.endFrame()

    #expect(interaction.navigationPath.isEmpty)
    #expect(interaction.activeCommandPath == common)
    interaction.processInput(InputState(commands: [command]))
    #expect(calls == ["common", "root"])

    calls = []
    interaction.focus(WidgetID("right"))
    interaction.processInput(InputState(commands: [command]))
    #expect(calls == ["right"])
  }

  @Test func ignoredCommandCanReplaceRootDuringScopedDispatch() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let target = FocusTarget()
    var calls: [String] = []
    runtime.build = { buffer, context in
      let button = buffer.focus(target, context: context.childScope(0)) { buffer, context in
        buffer.button(Button("Before") {}, context: context)
      }
      let scoped = buffer.onCommand(button, .action(.submit), context: context.childScope(0)) {
        calls.append("replace")
        runtime.build = { buffer, context in
          buffer.button(Button("After") {}, context: context)
        }
        return .ignored
      }
      return buffer.stack([scoped], axis: .vertical, context: context)
    }
    target.focus()
    _ = runtime.render(viewport: Size(width: 100, height: 100), input: InputState(), onChange: {})
    #expect(target.isFocused)
    let list = runtime.render(
      viewport: Size(width: 100, height: 100),
      input: InputState(commands: [.action(.submit)]), onChange: {})
    #expect(calls == ["replace"])
    #expect(
      list.paintSnapshot.contains {
        if case .text(_, "After", _, _) = $0 { return true }
        return false
      })
  }

  @Test func equalScopeHandlersAndActionRolesKeepRegistrationOrder() {
    let interaction = Interaction()
    let command = Command.application("test")
    var calls: [String] = []
    interaction.beginFrame(input: InputState())
    interaction.beginGroup(rect: rect)
    let scope = interaction.builderPath
    interaction.building.commandHandlers = [
      .init(
        path: scope, command: command,
        action: {
          calls.append("first")
          return .ignored
        }),
      .init(
        path: scope, command: command,
        action: {
          calls.append("second")
          return .handled
        }),
      .init(
        path: scope, command: command,
        action: {
          calls.append("third")
          return .handled
        }),
    ]
    interaction.building.actionRoles = [
      .init(path: scope, role: .defaultAction, action: { calls.append("first default") }),
      .init(path: scope, role: .defaultAction, action: { calls.append("second default") }),
    ]
    interaction.registerLeaf(id: WidgetID("leaf"), rect: rect)
    interaction.endGroup()
    interaction.endFrame()
    interaction.focus(WidgetID("leaf"))
    interaction.processInput(InputState(commands: [command, .action(.submit)]))
    #expect(calls == ["first", "second", "first default"])
  }

  @Test func unchangedFocusedCommitsDoNotInvalidateDiagnosticObservation() {
    let interaction = Interaction()
    let id = WidgetID("leaf")
    func commit() {
      interaction.beginFrame(input: InputState())
      interaction.registerLeaf(id: id, rect: rect)
      interaction.endFrame()
    }
    commit()
    interaction.focus(id)
    let changes = Mutex(0)
    for _ in 0..<3 {
      withObservationTracking(options: .didSet) {
        _ = interaction.selectionDescription
      } onChange: { event in
        event.cancel()
        changes.withLock { $0 += 1 }
      }
      commit()
      #expect(interaction.selectedLeafID == id)
    }
    #expect(changes.withLock { $0 } == 0)
    #expect(interaction.selectionDescription == "0 (leaf)")
  }

  @Test func keyedSelectionReconcilesAcrossReusableStorage() {
    let interaction = Interaction()
    let first = WidgetID("first")
    let second = WidgetID("second")
    func commit(_ ids: [WidgetID]) {
      interaction.beginFrame(input: InputState())
      interaction.beginGroup(rect: rect, navigationID: WidgetID("panel"))
      for id in ids { interaction.registerLeaf(id: id, rect: rect) }
      interaction.endGroup()
      interaction.endFrame()
    }
    commit([first, second])
    interaction.focus(second, editing: true)
    let oldStorage = interaction.tree!.storage
    let oldGeneration = oldStorage.generation
    commit([second, first])
    #expect(interaction.selectedLeafID == second)
    #expect(interaction.tree?.storage !== oldStorage)
    #expect(interaction.navigation?.node(at: interaction.navigationPath)?.renderPath == interaction.selection)
    #expect(interaction.editingLeaf == second)
    commit([first])
    #expect(oldStorage.generation != oldGeneration)
    #expect(interaction.selectedLeafID == first)
    #expect(interaction.editingLeaf == nil)
  }
}
