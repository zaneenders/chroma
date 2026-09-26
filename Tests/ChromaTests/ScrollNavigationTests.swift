import Testing

@testable import Chroma

@MainActor
struct ScrollNavigationTests {
  @MainActor private final class Harness {
    let context = RenderContext()
    let producer = FrameProducer()

    func render(_ content: any Block, input: InputState = InputState()) {
      _ = producer.render(
        content: content, viewport: Size(width: 200, height: 100),
        input: input, context: context, onChange: {})
    }
  }

  @Test func stepOutEscapesDeepVirtualizedRowsInOneStep() {
    let harness = Harness()
    let controller = ScrollViewController()
    let listID = WidgetID("scroll-escape-list")
    let after = FocusTarget()
    let rows = (0..<40).map { _ in FocusTarget() }
    let content = VStack {
      LazyVStack(id: listID, data: rows.indices, rowHeight: 20, controller: controller) { index in
        Button("Row \(index)") {}.focusTarget(rows[index])
      }
      Button("After") {}.focusTarget(after)
    }

    harness.render(content)
    #expect(rows[0].isFocused)
    for _ in 0..<12 {
      harness.render(content, input: InputState(commands: [.navigation(.down)]))
    }
    #expect(rows[12].isFocused)
    #expect(harness.context.interaction.scrollOffset(for: listID) > 0)

    // A single step out leaves the list; no walking back to the top is needed.
    harness.render(content, input: InputState(commands: [.navigation(.stepOut)]))
    #expect(after.isFocused)
    #expect(!rows.contains { $0.isFocused })

    // Stepping back in returns to the remembered row, not the first one.
    harness.render(content, input: InputState(commands: [.navigation(.stepIn)]))
    #expect(rows[12].isFocused)
  }

  @Test func stepInRestoresAVirtualizedRowByRevealingIt() {
    let harness = Harness()
    let controller = ScrollViewController()
    let listID = WidgetID("scroll-restore-list")
    let after = FocusTarget()
    let rows = (0..<40).map { _ in FocusTarget() }
    let content = VStack {
      LazyVStack(id: listID, data: rows.indices, rowHeight: 20, controller: controller) { index in
        Button("Row \(index)") {}.focusTarget(rows[index])
      }
      Button("After") {}.focusTarget(after)
    }

    harness.render(content)
    for _ in 0..<12 {
      harness.render(content, input: InputState(commands: [.navigation(.down)]))
    }
    #expect(rows[12].isFocused)
    harness.render(content, input: InputState(commands: [.navigation(.stepOut)]))
    #expect(after.isFocused)

    // Scrolling the list back to the top discards the remembered row entirely.
    controller.scrollToTop()
    harness.render(content)
    #expect(harness.context.interaction.scrollOffset(for: listID) == 0)
    #expect(!rows.contains { $0.isFocused })

    // Stepping in must scroll the remembered row back into view and focus it.
    harness.render(content, input: InputState(commands: [.navigation(.stepIn)]))
    #expect(harness.context.interaction.scrollOffset(for: listID) > 0)
    #expect(rows[12].isFocused)
  }

  @Test func stepInEntersTheNearestUnvisitedScrollContainer() {
    let harness = Harness()
    let before = FocusTarget()
    let rows = (0..<10).map { _ in FocusTarget() }
    let content = VStack {
      Button("Before") {}.focusTarget(before)
      LazyVStack(
        data: rows.indices, rowHeight: 20, controller: ScrollViewController()
      ) { index in
        Button("Row \(index)") {}.focusTarget(rows[index])
      }
    }

    harness.render(content)
    #expect(before.isFocused)

    harness.render(content, input: InputState(commands: [.navigation(.stepIn)]))
    #expect(rows[0].isFocused)
  }

  @Test func stepOutSkipsSiblingScrollContainers() {
    let harness = Harness()
    let leftList = WidgetID("scroll-left-list")
    let rightList = WidgetID("scroll-right-list")
    let left = FocusTarget()
    let leftRows = (0..<20).map { _ in FocusTarget() }
    let rightRows = (0..<20).map { _ in FocusTarget() }
    let content = HStack {
      Button("Left") {}.focusTarget(left)
      LazyVStack(id: leftList, data: leftRows.indices, rowHeight: 20, controller: ScrollViewController()) {
        index in
        Button("L\(index)") {}.focusTarget(leftRows[index])
      }
      LazyVStack(id: rightList, data: rightRows.indices, rowHeight: 20, controller: ScrollViewController()) {
        index in
        Button("R\(index)") {}.focusTarget(rightRows[index])
      }
    }

    harness.render(content)
    #expect(left.isFocused)

    // Stepping in enters the nearest list; walking it, then stepping out, must never
    // dive into the sibling list on the way.
    harness.render(content, input: InputState(commands: [.navigation(.stepIn)]))
    #expect(leftRows[0].isFocused)
    for _ in 0..<12 {
      harness.render(content, input: InputState(commands: [.navigation(.down)]))
    }
    #expect(leftRows[12].isFocused)

    harness.render(content, input: InputState(commands: [.navigation(.stepOut)]))
    #expect(left.isFocused)
    #expect(!rightRows.contains { $0.isFocused })

    // Stepping in from the button returns to the nearest list at its remembered row.
    harness.render(content, input: InputState(commands: [.navigation(.stepIn)]))
    #expect(leftRows[12].isFocused)
  }

  @Test func stepCommandsDoNothingWithoutScrollContainers() {
    let harness = Harness()
    let first = FocusTarget()
    let second = FocusTarget()
    let content = VStack {
      Button("First") {}.focusTarget(first)
      Button("Second") {}.focusTarget(second)
    }

    harness.render(content)
    #expect(first.isFocused)

    harness.render(content, input: InputState(commands: [.navigation(.stepOut)]))
    #expect(first.isFocused)
    harness.render(content, input: InputState(commands: [.navigation(.stepIn)]))
    #expect(first.isFocused)
  }

  @Test func layoutChangesInvalidateVirtualizedRowCoordinates() {
    let harness = Harness()
    let controller = ScrollViewController()
    let listID = WidgetID("scroll-layout-change")
    let keys = (0..<30).map { index in "row-\(index)" }
    let targets = Dictionary(uniqueKeysWithValues: keys.map { ($0, FocusTarget()) })
    let outside = FocusTarget()

    func content(_ order: [String]) -> any Block {
      VStack {
        LazyVStack(
          id: listID,
          controller: controller,
          rows: order.map { LazyVStack.Row(id: $0, content: Button($0) {}.focusTarget(targets[$0]!)) })
        Button("Outside") {}.focusTarget(outside)
      }
    }

    let original = content(keys)
    harness.render(original)
    for _ in 0..<20 {
      harness.render(original, input: InputState(commands: [.navigation(.down)]))
    }
    #expect(targets[keys[20]]!.isFocused)
    harness.render(original, input: InputState(commands: [.navigation(.stepOut)]))
    controller.scrollToTop()
    harness.render(original)

    let resized = content(keys)
    controller.lazyStackCache.measurements[0] = LazyRowMeasurement { Size(width: 200, height: 40) }
    harness.render(resized)
    harness.render(resized, input: InputState(commands: [.navigation(.stepIn)]))
    #expect(harness.context.interaction.pendingFocus == nil)
  }

  @Test func stepKeysInsertTextWhileEditing() {
    let harness = Harness()
    let field = FocusTarget()
    var text = ""
    let content = TextField(text: { text }, onChange: { text = $0 }).focusTarget(field)

    field.focus(editing: true)
    harness.render(content)

    for character in ["s", "l"] {
      guard
        let resolved = harness.context.interaction.resolve(
          KeyboardInput(chord: KeyChord(Character(character)), text: character),
          appBindings: .vimNavigation)
      else {
        Issue.record("\(character) did not resolve while editing")
        continue
      }
      #expect(resolved == .text(.insert(character)))
      harness.render(content, input: InputState(textEvents: [.insert(character)]))
    }
    #expect(text == "sl")
    #expect(field.isEditing)
  }

  @Test func stepKeysNavigateOutsideEditing() {
    let harness = Harness()
    let rows = (0..<10).map { _ in FocusTarget() }
    let after = FocusTarget()
    let content = VStack {
      LazyVStack(
        data: rows.indices, rowHeight: 20, controller: ScrollViewController()
      ) { index in
        Button("Row \(index)") {}.focusTarget(rows[index])
      }
      Button("After") {}.focusTarget(after)
    }

    harness.render(content)
    #expect(
      harness.context.interaction.resolve(
        KeyboardInput(chord: KeyChord("s"), text: "s"), appBindings: .vimNavigation)
        == .command(.navigation(.stepOut)))
    #expect(
      harness.context.interaction.resolve(
        KeyboardInput(chord: KeyChord("l"), text: "l"), appBindings: .vimNavigation)
        == .command(.navigation(.stepIn)))

    // The preset bindings drive the same flow as the raw commands.
    harness.render(
      content, input: InputState(commands: [.navigation(.down), .navigation(.stepOut)]))
    #expect(after.isFocused)
    harness.render(content, input: InputState(commands: [.navigation(.stepIn)]))
    #expect(rows[1].isFocused)
  }
}

extension KeyBindingsTests {
  @Test func vimNavigationBindsStepKeysToScopeMovement() {
    #expect(
      KeyBindings.vimNavigation.command(for: KeyChord("s")) == .some(.some(.navigation(.stepOut))))
    #expect(
      KeyBindings.vimNavigation.command(for: KeyChord("l")) == .some(.some(.navigation(.stepIn))))
    #expect(
      KeyBindings.vimNavigation.command(for: KeyChord("s"), isTextEditing: true) == nil)
    #expect(
      KeyBindings.vimNavigation.command(for: KeyChord("l"), isTextEditing: true) == nil)
  }
}
