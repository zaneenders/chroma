import Observation
import Synchronization
import Testing

@testable import Chroma

@MainActor
struct StructuralInteractionTests {
  @MainActor private final class Harness {
    let runtime = WindowRuntime()
    var context: LayoutContext { runtime.context }
    private var currentContent: LayoutBuilder = { buffer, context in
      return buffer.empty(context: context)
    }

    init() {
      runtime.build = { [unowned self] buffer, context in
        currentContent(&buffer, context)
      }
    }

    func render(_ content: @escaping LayoutBuilder, input: InputState = InputState()) {
      let isInitialFrame = context.interaction.tree == nil
      currentContent = content
      _ = runtime.render(
        viewport: Size(width: 200, height: 100),
        input: input, onChange: {})
      if isInitialFrame, context.interaction.selection == nil { context.interaction.focusFirstControlForTest() }
    }

    var press: InputState {
      InputState(
        pointerPosition: Point(x: 5, y: 5), pointerPressPosition: Point(x: 5, y: 5),
        pointerDown: true, pointerPressed: true)
    }

    var release: InputState {
      InputState(pointerPosition: Point(x: 5, y: 5), pointerReleased: true)
    }
  }

  @Test func keyPathCollectionPreservesEditingAcrossReordering() {
    @MainActor final class Entry {
      let value: Int
      var key: Int { value }
      init(_ value: Int) { self.value = value }
    }
    let harness = Harness()
    let target = FocusTarget()
    func content(_ keys: [Int]) -> LayoutBuilder {
      { buffer, context in
        var children: [LayoutNode] = []
        for entry in keys.map({ Entry($0) }) {
          let rowContext = context.childScope(0).keyed(entry.key)
          if entry.key == 1 {
            children.append(
              buffer.focus(target, context: rowContext) { buffer, context in
                buffer.textEditor(TextEditor(singleLine: true, text: { "hello" }, onChange: { _ in }), context: context)
              })
          } else {
            children.append(buffer.button(Button("Other") {}, context: rowContext))
          }
        }
        return buffer.stack(children, axis: .vertical, context: context)
      }
    }
    target.focus(editing: true)
    harness.render(content([1, 2]))
    let original = harness.context.interaction.editingLeaf
    harness.render(content([2, 3, 1]))
    #expect(original != nil)
    #expect(harness.context.interaction.editingLeaf == original)
    #expect(target.isFocused && target.isEditing)
  }

  @Test func explicitIdentityResetsEditingAndDoesNotRestoreIt() {
    let harness = Harness()
    let target = FocusTarget()
    func content(_ key: Int) -> LayoutBuilder {
      { buffer, context in
        buffer.focus(target, context: context.keyed(key)) { buffer, context in
          buffer.textEditor(TextEditor(singleLine: true, text: { "hello" }, onChange: { _ in }), context: context)
        }
      }
    }
    target.focus(editing: true)
    harness.render(content(1))
    let original = harness.context.interaction.editingLeaf
    harness.render(content(1))
    #expect(harness.context.interaction.editingLeaf == original)
    harness.render(content(2))
    #expect(!target.isEditing)
    #expect(harness.context.interaction.selectedLeafID != original)
    harness.render(content(1))
    #expect(harness.context.interaction.selectedLeafID == original)
    #expect(!target.isEditing)
  }

  @Test func explicitIdentityResetsScrollAndSelection() {
    let harness = Harness()
    let controller = ScrollViewController()
    func content(_ key: Int) -> LayoutBuilder {
      { buffer, context in
        let scroll = ScrollView(
          controller: controller,
          build: { buffer, context in
            let text = buffer.text(Text("hello").selectable(), context: context)
            return buffer.sizing(text, y: .fixed(500), context: context)
          })
        return buffer.scrollView(scroll, context: context.keyed(key))
      }
    }
    harness.render(content(1))
    harness.context.interaction.selectAll(at: Point(x: 1, y: 1))
    controller.scroll(to: 30)
    harness.render(content(1))
    #expect(harness.context.interaction.scrollStates.mapValues { $0.offset.y }.values.contains(30))
    #expect(harness.context.interaction.copyText() != nil)
    harness.render(content(2))
    #expect(harness.context.interaction.scrollStates.mapValues { $0.offset.y }.values.allSatisfy { $0 == 0 })
    #expect(harness.context.interaction.copyText() == nil)
    harness.render(content(1))
    #expect(harness.context.interaction.scrollStates.mapValues { $0.offset.y }.values.allSatisfy { $0 == 0 })
    #expect(harness.context.interaction.copyText() == nil)
  }

  @Test func focusQueriesObserveResolvedStateAndRemoval() {
    let harness = Harness()
    let first = FocusTarget()
    let second = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node346 = buffer.focus(
        first, context: context.childScope(0),
        content: { buffer, context in
          let node345 = buffer.textEditor(
            TextEditor(singleLine: true, text: { "hello" }, onChange: { _ in }), context: context)
          return node345
        })
      let node348 = buffer.focus(
        second, context: context.childScope(1),
        content: { buffer, context in
          let node347 = buffer.textEditor(
            TextEditor(singleLine: true, text: { "other" }, onChange: { _ in }), context: context)
          return node347
        })
      return buffer.stack([node346, node348], axis: .vertical, context: context)
    }
    let changed = Mutex(false)
    withObservationTracking {
      #expect(!first.isFocused && !first.isEditing)
    } onChange: {
      changed.withLock { $0 = true }
    }
    first.focus(editing: true)
    #expect(!first.isFocused && !first.isEditing)
    harness.render(content)
    #expect(changed.withLock { $0 })
    #expect(first.isFocused && first.isEditing)
    #expect(!second.isFocused && !second.isEditing)
    changed.withLock { $0 = false }
    withObservationTracking {
      #expect(first.isEditing)
    } onChange: {
      changed.withLock { $0 = true }
    }
    harness.context.interaction.endEditing()
    #expect(changed.withLock { $0 })
    #expect(first.isFocused && !first.isEditing)
    second.focus(editing: true)
    harness.render(content)
    #expect(!first.isFocused && !first.isEditing)
    #expect(second.isFocused && second.isEditing)
    harness.render({ buffer, context in
      return buffer.empty(context: context)
    })
    #expect(!second.isFocused && !second.isEditing)
    harness.render(content)
    #expect(!second.isEditing)
    harness.context.interaction.resetRegistrations()
    #expect(!first.isFocused && !second.isFocused)
  }

  @Test(arguments: ["horizontal", "vertical", "overlay"])
  func rawTupleChildrenHaveIndependentActions(container: String) {
    let harness = Harness()
    var calls: [String] = []
    let content: LayoutBuilder = { buffer, context in
      let a = buffer.button(Button("A") { calls.append("A") }, context: context.childScope(0))
      let b = buffer.button(Button("B") { calls.append("B") }, context: context.childScope(1))
      switch container {
      case "horizontal": return buffer.stack([a, b], axis: .horizontal, context: context)
      case "vertical": return buffer.stack([a, b], axis: .vertical, context: context)
      default: return buffer.overlay([a, b], context: context)
      }
    }
    harness.render(content)
    #expect(harness.context.interaction.registrations.buttonActions.count == 2)
    harness.render(content, input: InputState(commands: [.action(.activate)]))
    #expect(calls == ["A"])
  }

  @Test func collectionModifiersPreservePressAndSeparateBackgroundActions() {
    struct Item: Identifiable { let id: Int }
    let harness = Harness()
    var activations = 0
    func content(styled: Bool) -> LayoutBuilder {
      { buffer, context in
        var children: [LayoutNode] = []
        for item in [Item(id: 1), Item(id: 2)] {
          let rowContext = context.childScope(0).keyed(item.id)
          if styled {
            let row = buffer.background(
              context: rowContext,
              content: { buffer, context in
                let button = buffer.button(Button("Row") { activations += 1 }, context: context)
                return buffer.padding(button, 0, context: context)
              },
              background: { buffer, context in
                buffer.button(Button("Background") {}, context: context)
              })
            children.append(row)
          } else {
            children.append(buffer.button(Button("Row") { activations += 1 }, context: rowContext))
          }
        }
        return buffer.stack(children, axis: .vertical, context: context)
      }
    }
    harness.render(content(styled: false), input: harness.press)
    let id = harness.context.interaction.pressedLeaf
    #expect(id != nil)
    let styled = content(styled: true)
    harness.render(styled, input: harness.release)
    #expect(activations == 1)
    #expect(harness.context.interaction.selectedLeafID == id)
    #expect(harness.context.interaction.registrations.buttonActions.count == 4)
  }

  @Test func collectionModifiersPreserveEditingAcrossReordering() {
    struct Item: Identifiable { let id: Int }
    let harness = Harness()
    let target = FocusTarget()
    var text = ""
    func content(_ ids: [Int], styled: Bool) -> LayoutBuilder {
      { buffer, context in
        var children: [LayoutNode] = []
        for item in ids.map({ Item(id: $0) }) {
          let rowContext = context.childScope(0).keyed(item.id)
          var child: LayoutNode
          if item.id == 1 {
            child = buffer.focus(target, context: rowContext) { buffer, context in
              buffer.textEditor(TextEditor(singleLine: true, text: { text }, onChange: { text = $0 }), context: context)
            }
          } else {
            child = buffer.button(Button("Other") {}, context: rowContext)
          }
          if styled {
            child = buffer.padding(child, 0, context: rowContext)
            child = buffer.clip(child, context: rowContext)
          }
          children.append(child)
        }
        return buffer.stack(children, axis: .vertical, context: context)
      }
    }
    target.focus(editing: true)
    harness.render(content([1, 2], styled: false))
    let id = harness.context.interaction.editingLeaf
    #expect(id != nil)
    harness.render(content([2, 1], styled: true), input: InputState(textEvents: [.insert("x")]))
    #expect(harness.context.interaction.editingLeaf == id)
    #expect(text == "x")
  }

  @Test func labelChangesPreserveFocusAndPress() {
    let harness = Harness()
    var activations = 0
    harness.render(
      { buffer, context in
        return buffer.button(Button("Before") { activations += 1 }, context: context)
      }, input: harness.press)
    let id = harness.context.interaction.pressedLeaf
    #expect(id != nil)
    harness.render(
      { buffer, context in
        return buffer.button(Button("After") { activations += 1 }, context: context)
      },
      input: InputState(pointerPosition: Point(x: 5, y: 5), pointerDown: true))
    #expect(harness.context.interaction.pressedLeaf == id)
    #expect(harness.context.interaction.selectedLeafID == id)
    harness.render(
      { buffer, context in
        return buffer.button(Button("After") { activations += 1 }, context: context)
      }, input: harness.release)
    #expect(activations == 1)
  }

  @Test func branchReplacementCannotReceiveRelease() {
    let harness = Harness()
    var activations = 0
    func content(_ first: Bool) -> LayoutBuilder {
      { buffer, context in
        let child = buffer.button(
          Button(first ? "First" : "Second") { activations += 1 },
          context: context.childScope(0).keyed(first))
        return buffer.stack([child], axis: .vertical, context: context)
      }
    }
    harness.render(content(true), input: harness.press)
    let original = harness.context.interaction.pressedLeaf
    harness.render(content(false), input: harness.release)
    #expect(activations == 0)
    #expect(harness.context.interaction.pressedLeaf == nil)
    #expect(harness.context.interaction.selectedLeafID != original)
  }

  @Test func removalAndReinsertionCancelPress() {
    let harness = Harness()
    var activations = 0
    let button: LayoutBuilder = { buffer, context in
      return buffer.button(Button("Button") { activations += 1 }, context: context)
    }
    harness.render(button, input: harness.press)
    harness.render(
      { buffer, context in
        return buffer.empty(context: context)
      }, input: InputState(pointerDown: true))
    #expect(harness.context.interaction.pressedLeaf == nil)
    #expect(harness.context.interaction.selectedLeafID == nil)
    harness.render(button, input: harness.release)
    #expect(activations == 0)
  }

  @Test func releaseUsesCurrentActionAndDoesNotReplayIt() {
    let harness = Harness()
    var oldActions = 0
    var newActions = 0
    harness.render(
      { buffer, context in
        return buffer.button(Button("Button") { oldActions += 1 }, context: context)
      }, input: harness.press)
    harness.render(
      { buffer, context in
        return buffer.button(Button("Button") { newActions += 1 }, context: context)
      }, input: harness.release)
    harness.render({ buffer, context in
      return buffer.button(Button("Button") { newActions += 1 }, context: context)
    })
    #expect(oldActions == 0)
    #expect(newActions == 1)
  }

  @Test func removedDefaultActionCannotReceiveSubmit() {
    let harness = Harness()
    var activations = 0
    harness.render({ buffer, context in
      return buffer.button(Button("Submit", role: .defaultAction) { activations += 1 }, context: context)
    })
    harness.render(
      { buffer, context in
        return buffer.empty(context: context)
      }, input: InputState(commands: [.action(.submit)]))
    #expect(activations == 0)
  }

  @Test func explicitAndStructuralIDsCannotAlias() {
    let context = LayoutContext()
    #expect(context.widgetID != WidgetID(rawValue: 0))
    #expect(context.widgetID == context.widgetID)
    #expect(context.childScope(0).widgetID != context.childScope(1).widgetID)
  }

  private struct Item: Identifiable { let id: Int }

  private struct ItemButton {
    @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
      buffer.button(Button(String(item.id)) {}, context: context.component(Self.self))
    }

    let item: Item
  }

  @Test func keyedComponentInstancesKeepIndependentFocus() {
    let harness = Harness()
    func content(_ ids: [Int]) -> LayoutBuilder {
      { buffer, context in
        var children: [LayoutNode] = []
        for item in ids.map({ Item(id: $0) }) {
          children.append(ItemButton(item: item).build(into: &buffer, context: context.childScope(0).keyed(item.id)))
        }
        return buffer.stack(children, axis: .vertical, context: context)
      }
    }
    harness.render(content([1, 2]), input: harness.press)
    let first = harness.context.interaction.pressedLeaf
    harness.render(content([2, 3, 1]), input: InputState(pointerPosition: Point(x: 5, y: 5), pointerDown: true))
    #expect(harness.context.interaction.pressedLeaf == first)
    #expect(harness.context.interaction.selectedLeafID == first)
    #expect(harness.context.interaction.selection == [0, 2])
  }

  @Test func implicitTextEditorPreservesEditingAcrossRebuilds() {
    let harness = Harness()
    var text = "hello"
    func field(_ placeholder: String) -> LayoutBuilder {
      { buffer, context in
        buffer.textEditor(
          TextEditor(placeholder, singleLine: true, text: { text }, onChange: { text = $0 }), context: context)
      }
    }
    harness.render(field("Before"))
    harness.render(field("Before"), input: InputState(commands: [.action(.activate)]))
    let id = harness.context.interaction.editingLeaf
    #expect(id != nil)
    harness.render(field("After"), input: InputState(textEvents: [.insert("!")]))
    #expect(text == "hello!")
    #expect(harness.context.interaction.editingLeaf == id)
    harness.render(
      { buffer, context in
        return buffer.empty(context: context)
      }, input: InputState(textEvents: [.insert("ignored")]))
    #expect(text == "hello!")
    #expect(harness.context.interaction.editingLeaf == nil)
  }

  @Test func implicitScrollViewsHaveIndependentOffsets() {
    let harness = Harness()
    func content() -> LayoutBuilder {
      { buffer, context in
        var children: [LayoutNode] = []
        for (index, label) in ["left", "right"].enumerated() {
          let scroll = ScrollView(build: { buffer, context in
            let text = buffer.text(Text(label), context: context)
            return buffer.sizing(text, y: .fixed(500), context: context)
          })
          children.append(buffer.scrollView(scroll, context: context.childScope(index)))
        }
        return buffer.stack(children, axis: .horizontal, context: context)
      }
    }
    harness.render(content())
    harness.render(
      content(),
      input: InputState(
        pointerPosition: Point(x: 5, y: 5),
        scrollDelta: Point(x: 0, y: -30)))
    let offsets = harness.context.interaction.scrollStates.mapValues { $0.offset.y }
    #expect(offsets.count == 2)
    #expect(offsets.values.sorted() == [0, 30])
    harness.render(content())
    #expect(harness.context.interaction.scrollStates.mapValues { $0.offset.y } == offsets)
  }

  @Test func implicitLazyStackAndInteractiveRegisterIndependently() {
    let harness = Harness()
    var activations = 0
    let controller = ScrollViewController()
    func content() -> LayoutBuilder {
      { buffer, context in
        let scroll = ScrollView(
          data: [Item(id: 1), Item(id: 2)], rowHeight: 40, controller: controller,
          build: { buffer, context, item in
            buffer.interactive(
              action: { activations += item.id },
              content: { buffer, context, _ in
                buffer.text(Text(String(item.id)), context: context)
              }, context: context)
          })
        return buffer.scrollView(scroll, context: context)
      }
    }
    harness.render(content(), input: harness.press)
    harness.render(content(), input: harness.release)
    #expect(activations == 1)
    #expect(harness.context.interaction.registrations.buttonActions.count == 2)
    #expect(harness.context.interaction.scrollStates.mapValues { $0.offset.y }.count == 1)
  }

  @Test func selectableTextUsesIdentityRatherThanCoordinates() {
    let harness = Harness()
    func content(_ first: Bool) -> LayoutBuilder {
      { buffer, context in
        let child = buffer.text(
          Text(first ? "first" : "second").selectable(), context: context.childScope(0).keyed(first))
        return buffer.stack([child], axis: .vertical, context: context)
      }
    }
    harness.render(content(true))
    let interaction = harness.context.interaction
    let original = interaction.tree!.node(at: interaction.tree!.hitTest(Point(x: 1, y: 1))!)!.leafID!
    interaction.selectAll(at: Point(x: 1, y: 1))
    #expect(interaction.documentRange(for: original) != nil)
    harness.render(content(false))
    let replacement = interaction.tree!.node(at: interaction.tree!.hitTest(Point(x: 1, y: 1))!)!.leafID!
    #expect(original != replacement)
    #expect(interaction.documentRange(for: replacement) == nil)
  }

  @Test func focusRequestBeforeTraversalBindsWithoutChangingIdentity() {
    let harness = Harness()
    let target = FocusTarget()
    let field: LayoutBuilder = { buffer, context in
      let node375 = buffer.textEditor(
        TextEditor(singleLine: true, text: { "hello" }, onChange: { _ in }), context: context)
      return node375
    }
    let bareHarness = Harness()
    bareHarness.render(field)
    let expected = bareHarness.context.interaction.selectedLeafID
    #expect(expected != nil)
    target.focus(editing: true)
    harness.render({ buffer, context in
      let node378 = buffer.focus(
        target, context: context,
        content: { buffer, context in
          let node376 = field(&buffer, context)
          return buffer.padding(node376, 4, context: context)
        })
      return node378
    })
    #expect(harness.context.interaction.editingLeaf == expected)
    #expect(target.pendingEditing == nil)
    let generation = harness.context.interaction.editingSessionGeneration
    harness.render({ buffer, context in
      let node380 = buffer.focus(
        target, context: context,
        content: { buffer, context in
          return field(&buffer, context)
        })
      return node380
    })
    #expect(harness.context.interaction.editingSessionGeneration == generation)
  }

  @Test func focusRequestAfterTraversalRequestsRedrawAndResolves() {
    let harness = Harness()
    let target = FocusTarget()
    func content() -> LayoutBuilder {
      { buffer, context in
        let first = buffer.button(Button("First") {}, context: context.childScope(0))
        let second = buffer.focus(target, context: context.childScope(1)) { buffer, context in
          buffer.button(Button("Second") {}, context: context)
        }
        return buffer.stack([first, second], axis: .vertical, context: context)
      }
    }
    harness.render(content())
    let first = harness.context.interaction.selectedLeafID
    _ = harness.context.interaction.consumeRedrawRequest()
    target.focus()
    #expect(harness.context.interaction.consumeRedrawRequest())
    harness.render(content())
    #expect(harness.context.interaction.selectedLeafID != first)
    #expect(harness.context.interaction.selection == [0, 1])
  }

  @Test func focusBindingInvalidatesOnRemovalAndRebindsAfterMove() {
    let harness = Harness()
    let target = FocusTarget()
    let field: LayoutBuilder = { buffer, context in
      let node382 = buffer.focus(
        target, context: context,
        content: { buffer, context in
          let node381 = buffer.textEditor(
            TextEditor(singleLine: true, text: { "hello" }, onChange: { _ in }), context: context)
          return node381
        })
      return node382
    }
    target.focus(editing: true)
    harness.render(field)
    let original = harness.context.interaction.editingLeaf
    target.focus(editing: true)
    harness.render({ buffer, context in
      return buffer.empty(context: context)
    })
    #expect(target.interaction == nil)
    #expect(target.pendingEditing == nil)
    #expect(harness.context.interaction.editingLeaf == nil)
    target.focus(editing: true)
    harness.render({ buffer, context in
      let node384 = field(&buffer, context.childScope(0))
      return buffer.stack([node384], axis: .vertical, context: context)
    })
    #expect(harness.context.interaction.editingLeaf != nil)
    #expect(harness.context.interaction.editingLeaf != original)
  }

  @Test func measurementDoesNotBindOrConsumeFocusRequest() {
    let target = FocusTarget()
    target.focus()
    let context = LayoutContext()
    _ = measureLayout(
      { buffer, context in
        buffer.focus(target, context: context) { buffer, context in
          buffer.button(Button("Button") {}, context: context)
        }
      },
      proposal: Size(width: 100, height: 100), context: context)
    #expect(target.interaction == nil)
    #expect(target.pendingEditing == false)
    #expect(context.interaction.building.focusTargets.isEmpty)
  }

  @Test func retainedControllerRestoresOffsetButNotTextSelection() {
    let harness = Harness()
    let controller = ScrollViewController()
    func content() -> LayoutBuilder {
      { buffer, context in
        let scroll = ScrollView(
          controller: controller,
          build: { buffer, context in
            let text = buffer.text(Text("hello").selectable(), context: context)
            return buffer.sizing(text, y: .fixed(500), context: context)
          })
        return buffer.scrollView(scroll, context: context)
      }
    }
    harness.render(content())
    harness.context.interaction.selectAll(at: Point(x: 1, y: 1))
    controller.scroll(to: 30)
    harness.render(content())
    #expect(harness.context.interaction.scrollStates.mapValues { $0.offset.y }.values.contains(30))
    harness.render({ buffer, context in
      return buffer.empty(context: context)
    })
    #expect(harness.context.interaction.scrollStates.mapValues { $0.offset.y }.isEmpty)
    #expect(harness.context.interaction.copyText() == nil)
    harness.render(content())
    #expect(harness.context.interaction.scrollStates.mapValues { $0.offset.y }.values.contains(30))
    #expect(harness.context.interaction.copyText() == nil)
  }

  @Test func virtualizedPressDoesNotReviveWhenRowReturns() {
    let harness = Harness()
    let controller = ScrollViewController()
    var activations = 0
    func content() -> LayoutBuilder {
      { buffer, context in
        let scroll = ScrollView(
          data: (0..<20).map { Item(id: $0) }, rowHeight: 40, controller: controller,
          build: { buffer, context, item in
            buffer.button(Button(String(item.id)) { activations += 1 }, context: context)
          })
        return buffer.scrollView(scroll, context: context)
      }
    }
    harness.render(content(), input: harness.press)
    let original = harness.context.interaction.pressedLeaf
    controller.scroll(to: 400)
    harness.render(content(), input: InputState(pointerDown: true))
    #expect(harness.context.interaction.pressedLeaf == nil)
    controller.scrollToTop()
    harness.render(content(), input: harness.release)
    #expect(harness.context.interaction.tree?.findLeaf(original!) != nil)
    #expect(activations == 0)
  }

}
