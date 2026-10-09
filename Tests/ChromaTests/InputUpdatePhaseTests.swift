import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct InputUpdatePhaseTests {
  final class State {
    var events: [String] = []
    var updates = 0
    var paints = 0
    var showing = true
  }
  struct Observer {
    @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        expandsHorizontally: false, expandsVertically: false,
        measure: { sizeThatFits($0, context: context) },
        register: { register(in: $0, context: context) },
        paint: { paint(into: &$0, in: $1, context: context) })
    }

    let state: State
    var focusRule: FocusRule { .decorative }
    @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size { proposal }
    @MainActor func register(in rect: Rect, context: LayoutContext) {
      state.updates += 1
      context.registerInputHandler { input in
        state.events.append(contentsOf: input.textEvents.map(String.init(describing:)))
        // A context capture is legal; teardown must release current handlers as well as nodes.
        _ = context.interactionMode
      }
    }
    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: LayoutContext) { state.paints += 1 }

  }

  @Test func beginningRegistrationDoesNotDispatchInput() {
    let state = State()
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    let node = Observer(state: state).build(into: &buffer, context: context)
    let rect = Rect(x: 0, y: 0, width: 20, height: 20)
    context.interaction.beginFrame(input: InputState())
    buffer.register(node, in: rect)
    context.interaction.endFrame()

    let event = InputState(textEvents: [.insert("a")])
    context.interaction.beginFrame(input: event)
    buffer.register(node, in: rect)
    context.interaction.endFrame()
    #expect(state.events.isEmpty)

    context.interaction.processInput(event)
    context.interaction.finishInput()
    #expect(state.events.count == 1)
  }

  @Test func rawObserversReceiveEveryEdgeOnceAndPresentationDoesNotReplayThem() {
    let state = State()
    let host = HeadlessHost()
    defer { host.close() }
    host.build = { buffer, context in
      return Observer(state: state).build(into: &buffer, context: context)
    }
    _ = host.renderIfNeeded()
    host.sendInput(InputState(textEvents: [.insert("a")]))
    host.sendInput(InputState(textEvents: [.insert("b")]))
    #expect(state.events.count == 2)
    _ = host.renderIfNeeded()
    #expect(state.events.count == 2)
    #expect(state.paints == 2)
  }

  @Test func replacedRootAndDestroyedHostReleaseObserversAndContextCycles() {
    weak var captured: State?
    var ownedHost: HeadlessHost? = HeadlessHost(size: Size(width: 20, height: 20))
    do {
      let state = State()
      captured = state
      ownedHost!.build = { buffer, context in
        return Observer(state: state).build(into: &buffer, context: context)
      }
      ownedHost!.render()
    }
    #expect(captured != nil)
    ownedHost = nil
    #expect(captured == nil)

    let host = HeadlessHost()
    do {
      let state = State()
      captured = state
      host.build = { buffer, context in
        return Observer(state: state).build(into: &buffer, context: context)
      }
      host.render()
    }
    host.build = { buffer, context in
      return buffer.empty(context: context)
    }
    #expect(captured == nil)
    host.close()
  }
  @Test func removedProviderDoesNotKeepCopyOrSelectAllCallbacks() {
    struct Provider {
      @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
        let context = context.component(Self.self)
        return buffer.customLeaf(
          context: context, focusRule: focusRule,
          expandsHorizontally: false, expandsVertically: false,
          measure: { sizeThatFits($0, context: context) },
          register: { register(in: $0, context: context) },
          paint: { paint(into: &$0, in: $1, context: context) })
      }

      var focusRule: FocusRule { .decorative }
      @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size { proposal }
      @MainActor func register(in rect: Rect, context: LayoutContext) {
        context.setCopyTextProvider { "old root" }
        context.setSelectAllHandler { true }
      }
      @MainActor func paint(into list: inout DrawList, in rect: Rect, context: LayoutContext) {}

    }
    let context = LayoutContext()
    let producer = FrameProducer()
    let state = State()
    let content: LayoutBuilder = { buffer, context in
      if state.showing { return Provider().build(into: &buffer, context: context) }
      return buffer.empty(context: context)
    }
    _ = producer.render(
      build: content, viewport: Size(width: 20, height: 20),
      input: InputState(),
      context: context, onChange: {})
    #expect(context.interaction.copyText() == "old root")
    state.showing = false
    producer.refreshRegistrations(
      content, viewport: Size(width: 20, height: 20),
      context: context)
    #expect(context.interaction.copyText() == nil)
    #expect(context.interaction.onSelectAll == nil)
  }

  @Test func opaquePaintingDoesNotConstructItsChildAgain() {
    struct Factory {
      let state: State
      @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
        state.updates += 1
        return buffer.text(Text(String(state.updates)), context: context.component(Self.self))
      }
    }
    let state = State()
    let host = HeadlessHost()
    defer { host.close() }
    host.build = { buffer, context in
      return Factory(state: state).build(into: &buffer, context: context)
    }
    host.render()
    #expect(state.updates == 2)  // Initial registration and first presentation update.
    let frame = host.render()
    #expect(state.updates == 3)
    #expect(
      frame.paintSnapshot.contains {
        if case .text(_, "3", _, _) = $0 { return true }
        return false
      })
  }

}
