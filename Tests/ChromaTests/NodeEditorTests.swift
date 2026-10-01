import Observation
import Testing

@testable import Chroma

@MainActor
struct NodeEditorTests {
  @Observable final class Model {
    var text = "abc"
    var visible = true
    var revision = 0
  }

  private final class Counts {
    var reads = 0
    var builds = 0
    var now = 100.0
    var changes: [String] = []
    var submits: [Int] = []
  }

  private let viewport = Size(width: 240, height: 80)

  private func activate(_ producer: NodeFrameProducer) throws {
    try producer.dispatch(InputState(commands: [.navigation(.nextFocus)]), onChange: {})
    try producer.dispatch(InputState(commands: [.action(.activate)]), onChange: {})
  }

  @Test func retainedEditorMatchesLegacyMeasurementAndPaint() throws {
    for singleLine in [true, false] {
      for text in ["", "abc", "a👨‍👩‍👧‍👦\nbc\ndefghijklmnopqrstuvwxyz"] {
        let context = BlockContext()
        let editor = TextEditor("Placeholder", singleLine: singleLine, text: { text }, onChange: { _ in })
        let scene = NodeScene()
        try scene.update(editor, context: context)
        let rect = Rect(origin: .zero, size: viewport)
        #expect(try scene.layout(in: rect) == editor.sizeThatFits(viewport, context: context))
        scene.prepare(viewport: viewport)
        let expected = scene.paint(cullingEnabled: false)
        context.interaction.beginFrame(input: InputState(), processingInput: false)
        var legacy = DrawList()
        BlockEngine.draw(editor, into: &legacy, in: rect, context: context)
        context.interaction.endFrame()
        #expect(expected.commands == legacy.commands)
      }
    }
  }

  @Test func caretBlinkHoverAndFocusReuseBuildLayoutAndRegistrations() throws {
    let counts = Counts()
    let model = Model()
    let producer = NodeFrameProducer(clock: { counts.now })
    let context = BlockContext()
    let editor = DeferredBlock {
      counts.builds += 1
      return TextEditor(
        singleLine: true,
        text: {
          counts.reads += 1
          return model.text
        }, onChange: { model.text = $0 })
    }
    try producer.refresh(content: editor, viewport: viewport, context: context, onChange: {})
    try activate(producer)
    let first = producer.paint()
    #expect(producer.needsAnimationFrame)
    let reads = counts.reads
    let builds = counts.builds
    let layouts = producer.layouts
    let measurements = producer.measurements
    let preparations = producer.preparations
    let textLayouts = producer.textLayoutBuilds
    let tree = context.interaction.tree
    counts.now = 100.8
    let hidden = producer.renderAnimations()
    counts.now = 101.3
    let visible = producer.renderAnimations()
    #expect(hidden.commands != first.commands)
    #expect(visible.commands == first.commands)
    #expect(context.interaction.tree === tree)
    #expect(counts.reads == reads)
    #expect(counts.builds == builds)
    #expect(producer.layouts == layouts)
    #expect(producer.measurements == measurements)
    #expect(producer.preparations == preparations)
    #expect(producer.textLayoutBuilds == textLayouts)
    try producer.dispatch(InputState(pointerPosition: Point(x: 10, y: 10)), onChange: {})
    #expect(counts.reads == reads)
    #expect(producer.layouts == layouts)
    #expect(producer.preparations == preparations)
    try producer.dispatch(InputState(textEvents: [.selectAll]), onChange: {})
    #expect(!producer.needsAnimationFrame)
    #expect(producer.layouts == layouts)
    #expect(producer.preparations == preparations)
    _ = producer.paint()
    #expect(!producer.needsAnimationFrame)
  }

  @Test func orderedTypingRefreshesTextWithoutBuildOrInputPaint() throws {
    let model = Model()
    let counts = Counts()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let editor = TextEditor(
      singleLine: true, text: { model.text },
      onChange: {
        model.text = $0
        counts.changes.append($0)
      })
    try producer.refresh(content: editor, viewport: viewport, context: context, onChange: {})
    try activate(producer)
    for text in ["d", "e", "f"] {
      try producer.refresh(content: editor, viewport: viewport, context: context, onChange: {})
      try producer.dispatch(InputState(textEvents: [.insert(text)]), onChange: {})
    }
    #expect(counts.changes == ["abcd", "abcde", "abcdef"])
    #expect(context.interaction.caretOffset == 6)
    #expect(producer.builds == 1)
    #expect(producer.paints == 0)
    #expect(
      producer.paint().commands.contains {
        if case .text(_, "abcdef", _, _) = $0 { true } else { false }
      })
    try producer.dispatch(InputState(textEvents: [.selectAll, .insert("👨‍👩‍👧‍👦")]), onChange: {})
    #expect(model.text.count == 1)
    #expect(context.interaction.caretOffset == 1)
  }

  @Test func unobservedTextAndResizeRefreshGeometryBeforeInput() throws {
    var text = "abcdef"
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let editor = TextEditor(text: { text }, onChange: { text = $0 })
    try producer.refresh(content: editor, viewport: viewport, context: context, onChange: {})
    try activate(producer)
    try producer.dispatch(InputState(textEvents: [.insert("g")]), onChange: {})
    try producer.dispatch(InputState(textEvents: [.insert("h")]), onChange: {})
    #expect(text == "abcdefgh")
    let builds = producer.textLayoutBuilds
    let narrow = Size(width: 40, height: 160)
    try producer.refresh(content: editor, viewport: narrow, context: context, onChange: {})
    #expect(producer.builds == 1)
    #expect(producer.textLayoutBuilds > builds)
    try producer.dispatch(InputState(textEvents: [.moveCaretUp]), onChange: {})
    #expect(context.interaction.caretOffset < text.count)
    #expect(context.interaction.viewport.size == narrow)
  }

  @Test func modelTextChangesRelayoutOnlyEditorMeasurementsAndUpdateSelection() throws {
    let model = Model()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let content = VStack {
      TextEditor(text: { model.text }, onChange: { model.text = $0 })
      Text("Sibling")
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let measurements = producer.measurements
    model.text = "one\ntwo\nthree"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(producer.measurements == measurements + 2)
    #expect(producer.builds == 1)
    try activate(producer)
    try producer.dispatch(InputState(textEvents: [.selectAll]), onChange: {})
    model.text = "X"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(context.interaction.caretOffset == 1)
    #expect(context.interaction.textSelectionRange == 0..<1)
    #expect(context.interaction.copyText() == "X")
  }

  @Test func sameIdentityReplacesEditorCallbacksBeforeSubmit() throws {
    let model = Model()
    let counts = Counts()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let content = UpdateBoundary {
      let revision = model.revision
      return TextEditor(
        singleLine: true, text: { model.text }, onChange: { model.text = $0 },
        onSubmit: { _ in counts.submits.append(revision) })
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    try activate(producer)
    let layouts = producer.layouts
    model.revision = 1
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    try producer.dispatch(InputState(textEvents: [.submit]), onChange: {})
    #expect(counts.submits == [1])
    #expect(producer.layouts == layouts)
    #expect(producer.paints == 0)
  }

  @Test func windowSchedulerUsesNodeCaretAnimationAndStopsOnRemovalOrEndEditing() {
    let counts = Counts()
    let model = Model()
    let runtime = WindowRuntime(clock: { counts.now })
    runtime.nodeLifecycleEnabled = true
    runtime.content = TextEditor(singleLine: true, text: { model.text }, onChange: { model.text = $0 })
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    let first = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    runtime.scheduler.recordProducedFrame()
    #expect(runtime.needsAnimationFrame)
    #expect(runtime.scheduler.nextFrame?.kind == .animation)
    counts.now += 0.8
    let hidden = runtime.renderScheduled(.animation, viewport: viewport, onChange: {})
    #expect(first.commands != hidden.commands)
    #expect(runtime.nodeBuilds == 1)
    #expect(runtime.nodePaints == 2)
    runtime.handleInput(InputState(textEvents: [.endEditing]))
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(!runtime.needsAnimationFrame)
    #expect(runtime.scheduler.nextFrame == nil)
    runtime.content = nil
    #expect(runtime.interaction.registrations.inputHandlers.isEmpty)
    #expect(!runtime.needsAnimationFrame)
    #expect(runtime.renderAnimations().commands.isEmpty)
    runtime.reset()
  }

  @Test func pointerDragAutoscrollAdvancesOnlyDuringInput() throws {
    let text = (0..<20).map { "row \($0)" }.joined(separator: "\n")
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let focus = FocusTarget()
    let editor = TextEditor(lineLimits: 1...2, text: { text }, onChange: { _ in }).focusTarget(focus)
    focus.focus(editing: true)
    let size = Size(width: 120, height: 80)
    try producer.refresh(content: editor, viewport: size, context: context, onChange: {})
    try producer.dispatch(InputState(textEvents: [.moveCaretToStart]), onChange: {})
    let point = Point(x: 10, y: 10)
    try producer.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true), onChange: {})
    let below = Point(x: 50, y: 100)
    try producer.dispatch(InputState(pointerPosition: below, pointerDown: true), onChange: {})
    let firstRow = try #require(context.interaction.textDragViewportRow)
    let selection = context.interaction.textSelectionRange
    let builds = producer.textLayoutBuilds
    _ = producer.paint()
    _ = producer.paint()
    #expect(context.interaction.textDragViewportRow == firstRow)
    #expect(context.interaction.textSelectionRange == selection)
    #expect(producer.textLayoutBuilds == builds)
    try producer.dispatch(InputState(pointerPosition: below, pointerDown: true), onChange: {})
    let secondRow = try #require(context.interaction.textDragViewportRow)
    #expect(secondRow == firstRow + 1)
    #expect(producer.textLayoutBuilds == builds)
  }

  @Test func editingSelectionPaintMatchesLegacyUsingTheSameLayout() throws {
    let model = Model()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let editor = TextEditor(singleLine: true, text: { model.text }, onChange: { model.text = $0 })
    try producer.refresh(content: editor, viewport: viewport, context: context, onChange: {})
    try activate(producer)
    try producer.dispatch(InputState(textEvents: [.selectAll]), onChange: {})
    let node = producer.paint()
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    var legacy = DrawList()
    BlockEngine.draw(editor, into: &legacy, in: Rect(origin: .zero, size: viewport), context: context)
    context.interaction.endFrame()
    #expect(node.commands == legacy.commands)
  }

  private final class LifetimeProbe {}

  @Test func removingObservedEditorReleasesCallbacksAndStopsBlink() throws {
    let model = Model()
    let counts = Counts()
    let runtime = WindowRuntime(clock: { counts.now })
    runtime.nodeLifecycleEnabled = true
    weak var removed: LifetimeProbe?
    func content() -> any Block {
      guard model.visible else { return EmptyBlock() }
      let probe = LifetimeProbe()
      removed = probe
      return TextEditor(
        text: { model.text },
        onChange: { [probe] in
          _ = probe
          model.text = $0
        })
    }
    runtime.content = UpdateBoundary { content() }
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(runtime.needsAnimationFrame)
    #expect(removed != nil)
    model.visible = false
    runtime.handleInput(InputState(textEvents: [.insert("Ignored")]))
    #expect(model.text == "abc")
    #expect(removed == nil)
    #expect(runtime.interaction.editingLeaf == nil)
    #expect(runtime.interaction.registrations.inputHandlers.isEmpty)
    #expect(!runtime.needsAnimationFrame)
    let frame = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(frame.commands.isEmpty)
    runtime.reset()
  }

  @Test func scheduledContentReadsUnobservedTextButAnimationDoesNot() {
    let counts = Counts()
    var text = "Old"
    let runtime = WindowRuntime(clock: { counts.now })
    runtime.nodeLifecycleEnabled = true
    runtime.content = TextEditor(
      singleLine: true,
      text: {
        counts.reads += 1
        return text
      }, onChange: { text = $0 })
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    text = "External"
    let changed = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(
      changed.commands.contains {
        if case .text(_, "External", _, _) = $0 { true } else { false }
      })
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    let reads = counts.reads
    _ = runtime.renderAnimations()
    #expect(counts.reads == reads)
    runtime.reset()
  }

  @Test func animationResizeRelayoutsBeforeReusingCaretSegments() {
    let counts = Counts()
    let runtime = WindowRuntime(clock: { counts.now })
    runtime.nodeLifecycleEnabled = true
    runtime.content = TextEditor(text: { "abc" }, onChange: { _ in })
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    let resized = Size(width: 80, height: 60)
    _ = runtime.renderScheduled(.animation, viewport: resized, onChange: {})
    #expect(runtime.interaction.viewport.size == resized)
    #expect(runtime.nodeBuilds == 1)
    #expect(runtime.nodePaints == 3)
    runtime.reset()
  }

  @Test func eightQueuedTextEventsShareOneScheduledPaint() {
    let counts = Counts()
    let model = Model()
    let runtime = WindowRuntime(clock: { counts.now })
    runtime.nodeLifecycleEnabled = true
    runtime.content = TextEditor(
      singleLine: true, text: { model.text },
      onChange: {
        model.text = $0
        counts.changes.append($0)
      })
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    for index in 0..<8 {
      runtime.dispatchInput { runtime.handleInput(InputState(textEvents: [.insert("\(index)")])) }
    }
    #expect(runtime.nodePaints == 1)
    let result = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(model.text == "abc01234567")
    #expect(counts.changes.count == 8)
    #expect(runtime.nodeBuilds == 1)
    #expect(runtime.nodePaints == 2)
    #expect(
      result.commands.contains {
        if case .text(_, "abc01234567", _, _) = $0 { true } else { false }
      })
    runtime.reset()
  }

  @Test func metricsScaleAndClippedOverflowRetainCorrectEditorOutput() throws {
    let model = Model()
    model.text = "one two three four five six"
    let scene = NodeScene()
    var context = BlockContext()
    let content = TextEditor(text: { model.text }, onChange: { model.text = $0 })
      .padding(-8).sizing(x: .fixed(20), y: .fixed(40)).clipped()
    let rect = Rect(origin: .zero, size: viewport)
    try scene.update(content, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: viewport)
    let initial = scene.textLayoutBuilds
    context.fontMetrics.cellAdvance *= 2
    try scene.layout(in: rect)
    scene.prepare(viewport: viewport)
    #expect(scene.textLayoutBuilds > initial)
    context.textScale = 2
    try scene.update(content, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: viewport)
    let expected = scene.paint(cullingEnabled: false)
    let culled = scene.paint()
    #expect(expected.commands == culled.commands)
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    var legacy = DrawList()
    BlockEngine.draw(content, into: &legacy, in: rect, context: context)
    context.interaction.endFrame()
    #expect(expected.commands == legacy.commands)
  }

  @Test func focusTargetAndPointerEditingUsePreparedGeometry() throws {
    let model = Model()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let focus = FocusTarget()
    let editor = TextEditor(singleLine: true, text: { model.text }, onChange: { model.text = $0 }).focusTarget(focus)
    try producer.refresh(content: editor, viewport: viewport, context: context, onChange: {})
    focus.focus(editing: true)
    try producer.refresh(content: editor, viewport: viewport, context: context, onChange: {})
    #expect(context.interaction.isTextEditing)
    let point = Point(x: 20, y: 10)
    try producer.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true), onChange: {})
    try producer.dispatch(InputState(pointerPosition: point, pointerReleased: true), onChange: {})
    #expect(context.interaction.caretOffset == 1)
    try producer.dispatch(InputState(textEvents: [.insert("X")]), onChange: {})
    #expect(model.text == "aXbc")
  }
}
