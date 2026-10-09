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
  struct Observer: Block {
    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
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
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    @MainActor func register(in rect: Rect, context: BlockContext) {
      state.updates += 1
      context.registerInputHandler { input in
        state.events.append(contentsOf: input.textEvents.map(String.init(describing:)))
        // A context capture is legal; teardown must release current handlers as well as nodes.
        _ = context.interactionMode
      }
    }
    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) { state.paints += 1 }

  }

  @Test func rawObserversReceiveEveryEdgeOnceAndPresentationDoesNotReplayThem() {
    let state = State()
    let host = HeadlessHost()
    defer { host.close() }
    host.setContent(Observer(state: state))
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
      ownedHost!.setContent(Observer(state: state))
      ownedHost!.render()
    }
    #expect(captured != nil)
    ownedHost = nil
    #expect(captured == nil)

    let host = HeadlessHost()
    do {
      let state = State()
      captured = state
      host.setContent(Observer(state: state))
      host.render()
    }
    host.setContent(EmptyBlock())
    #expect(captured == nil)
    host.close()
  }
  @Test func removedProviderDoesNotKeepCopyOrSelectAllCallbacks() {
    struct Provider: Block {
      @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
        let context = context.component(Self.self)
        return buffer.customLeaf(
          context: context, focusRule: focusRule,
          expandsHorizontally: false, expandsVertically: false,
          measure: { sizeThatFits($0, context: context) },
          register: { register(in: $0, context: context) },
          paint: { paint(into: &$0, in: $1, context: context) })
      }

      var focusRule: FocusRule { .decorative }
      @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
      @MainActor func register(in rect: Rect, context: BlockContext) {
        context.setCopyTextProvider { "old root" }
        context.setSelectAllHandler { true }
      }
      @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {}

    }
    let context = BlockContext()
    let producer = FrameProducer()
    let state = State()
    let content = DeferredBlock { if state.showing { Provider() } }
    _ = producer.render(
      build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 20, height: 20),
      input: InputState(),
      context: context, onChange: {})
    #expect(context.interaction.copyText() == "old root")
    state.showing = false
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 20, height: 20),
      context: context)
    #expect(context.interaction.copyText() == nil)
    #expect(context.interaction.onSelectAll == nil)
  }

  @Test func opaquePaintingDoesNotConstructItsChildAgain() {
    struct Factory: Block {
      let state: State
      @MainActor var child: some Block {
        state.updates += 1
        return Text(String(state.updates))
      }
      func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
        buffer.emit(child, context: context.component(Self.self))
      }
    }
    let state = State()
    let host = HeadlessHost()
    defer { host.close() }
    host.setContent(Factory(state: state))
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
