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
  struct Observer: PaintableBlock {
    let state: State
    var focusRule: FocusRule { .decorative }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func register(in rect: Rect, context: BlockContext) {
      state.updates += 1
      context.registerInputHandler { input in
        state.events.append(contentsOf: input.textEvents.map(String.init(describing:)))
        // A context capture is legal; teardown must release current handlers as well as nodes.
        _ = context.interactionMode
      }
    }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) { state.paints += 1 }

  }

  @Test func rawObserversReceiveEveryEdgeOnceAndPresentationDoesNotReplayThem() {
    let state = State()
    let host = HeadlessHost()
    defer { host.close() }
    host.content = Observer(state: state)
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
      ownedHost!.content = Observer(state: state)
      ownedHost!.render()
    }
    #expect(captured != nil)
    ownedHost = nil
    #expect(captured == nil)

    let host = HeadlessHost()
    do {
      let state = State()
      captured = state
      host.content = Observer(state: state)
      host.render()
    }
    host.content = EmptyBlock()
    #expect(captured == nil)
    host.close()
  }
  @Test func removedProviderDoesNotKeepCopyOrSelectAllCallbacks() {
    struct Provider: PaintableBlock {
      var focusRule: FocusRule { .decorative }
      func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
      func register(in rect: Rect, context: BlockContext) {
        context.setCopyTextProvider { "old root" }
        context.setSelectAllHandler { true }
      }
      func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {}

    }
    let context = BlockContext()
    let producer = FrameProducer()
    let state = State()
    let content = DeferredBlock { if state.showing { Provider() } }
    _ = producer.render(
      content: content, viewport: Size(width: 20, height: 20), input: InputState(),
      context: context, onChange: {})
    #expect(context.interaction.copyText() == "old root")
    state.showing = false
    producer.refreshRegistrations(content, viewport: Size(width: 20, height: 20), context: context)
    #expect(context.interaction.copyText() == nil)
    #expect(context.interaction.onSelectAll == nil)
  }

  @Test func opaquePaintingDoesNotConstructItsChildAgain() {
    struct Factory: LayoutPreparingBlock {
      let state: State
      var focusRule: FocusRule { .container }
      @MainActor var child: some Block {
        state.updates += 1
        return Text(String(state.updates))
      }
      func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
        let prepared = BlockEngine.prepare(child, context: context)
        return BlockEngine.Resolved(
          measure: { $0 }, register: prepared.register, paint: prepared.paint)
      }
    }
    let state = State()
    let host = HeadlessHost()
    defer { host.close() }
    host.content = Factory(state: state)
    host.render()
    #expect(state.updates == 2)  // Initial registration and first presentation update.
    let frame = host.render()
    #expect(state.updates == 3)
    #expect(
      frame.commands.contains {
        if case .text(_, "3", _, _) = $0 { return true }
        return false
      })
  }

}
