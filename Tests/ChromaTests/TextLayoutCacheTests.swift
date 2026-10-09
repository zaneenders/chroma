import Testing

@testable import Chroma

@MainActor
struct TextLayoutCacheTests {
  @Test func cacheKeysContainTextAndColumns() {
    let cache = TextLayoutPreparation()
    let original = cache.resolve("ab\ncd", columns: 10)
    #expect(cache.resolve("ab\ncd", columns: 10) === original)
    let changed = cache.resolve("ab\ncd\nef", columns: 10)
    let wrapped = cache.resolve("ab\ncd\nef", columns: 1)
    #expect(changed !== original)
    #expect(wrapped !== changed)
    #expect(changed.layout.lines.count == 3)
    #expect(wrapped.layout.lines.count == 6)
    #expect(cache.resolve("ab\ncd", columns: 10) === original)
    #expect(cache.count == 3)
  }

  @Test func canonicallyEquivalentTextKeepsItsActualSourceBytes() {
    let cache = TextLayoutPreparation()
    let composed = cache.resolve("\u{e9}", columns: nil)
    let decomposed = cache.resolve("e\u{301}", columns: nil)
    #expect(composed.text == decomposed.text)
    #expect(composed !== decomposed)
    #expect(composed != decomposed)
    #expect(Array(decomposed.text.utf8) == [0x65, 0xcc, 0x81])
    #expect(Array(decomposed.layout.lines[0].text.utf8) == [0x65, 0xcc, 0x81])
    #expect(cache.resolve("e\u{301}", columns: nil) === decomposed)
    #expect(cache.count == 2)
  }

  @Test func entryLimitEvictsOldestEvenWhenItWasReadRecently() {
    let cache = TextLayoutPreparation(entryLimit: 2)
    let first = cache.resolve("first", columns: nil)
    let second = cache.resolve("second", columns: nil)
    #expect(cache.resolve("first", columns: nil) === first)
    let third = cache.resolve("third", columns: nil)
    #expect(cache.count == 2)
    #expect(cache.resolve("second", columns: nil) === second)
    #expect(cache.resolve("third", columns: nil) === third)
    #expect(cache.resolve("first", columns: nil) !== first)
  }

  @Test func byteBudgetCountsUnicodeAndLinesAndEvictsOldSnapshots() {
    let ascii = TextLayoutSnapshot("abc", columns: nil)
    let unicode = TextLayoutSnapshot("世界語", columns: nil)
    let wrapped = TextLayoutSnapshot("abc", columns: 1)
    #expect(unicode.estimatedBytes > ascii.estimatedBytes)
    #expect(wrapped.estimatedBytes > ascii.estimatedBytes)
    let cache = TextLayoutPreparation(byteLimit: ascii.estimatedBytes + unicode.estimatedBytes - 1)
    weak let first = cache.resolve("abc", columns: nil)
    #expect(first != nil)
    _ = cache.resolve("世界語", columns: nil)
    #expect(first == nil)
    #expect(cache.count == 1)
    #expect(cache.estimatedBytes == unicode.estimatedBytes)
  }

  @Test func oversizedLayoutsAreNotRetainedOrAllowedToFlushUsefulEntries() {
    let small = TextLayoutSnapshot("small", columns: nil)
    let cache = TextLayoutPreparation(byteLimit: small.estimatedBytes)
    let retained = cache.resolve("small", columns: nil)
    let large = String(repeating: "界\n", count: 100)
    weak let oversized = cache.resolve(large, columns: nil)
    #expect(oversized == nil)
    #expect(cache.count == 1)
    #expect(cache.resolve("small", columns: nil) === retained)
    #expect(cache.estimatedBytes == small.estimatedBytes)
    let disabled = TextLayoutPreparation(entryLimit: 0)
    _ = disabled.resolve("small", columns: nil)
    #expect(disabled.count == 0)
    #expect(disabled.estimatedBytes == 0)
  }

  @Test func windowsHaveIndependentCachesThatResetAndRelease() {
    let first = Interaction()
    let second = Interaction()
    weak let snapshot = first.textLayouts.resolve("same", columns: nil)
    #expect(second.textLayouts.resolve("same", columns: nil) !== snapshot)
    first.beginFrame(input: InputState())
    first.endFrame()
    #expect(first.textLayouts.resolve("same", columns: nil) === snapshot)
    first.resetRegistrations()
    #expect(snapshot == nil)
    #expect(first.textLayouts.count == 0)
    #expect(first.textLayouts.estimatedBytes == 0)
    weak var released: TextLayoutSnapshot?
    do {
      let owner = Interaction()
      released = owner.textLayouts.resolve("temporary", columns: nil)
      #expect(released != nil)
    }
    #expect(released == nil)
  }

  @Test(arguments: ["plain", "wrapped", "selectable", "editor"])
  func freshFramesReuseImmutableShaping(kind: String) {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let content: any Block =
      switch kind {
      case "wrapped": Text("unchanged text").wrapping()
      case "selectable": Text("unchanged text").selectable()
      case "editor": TextEditor(text: { "unchanged text" }, onChange: { _ in })
      default: Text("unchanged text")
      }
    runtime.setContent(content)
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    for _ in 0..<4 {
      _ = runtime.render(viewport: Size(width: 200, height: 100), input: InputState(), onChange: {})
    }
    #expect(PipelineMetrics.snapshot.textLayouts == 1)
  }

  @Test func metricChangesRefreshGeometryAndOnlyReshapeWhenColumnsChange() {
    var context = BlockContext()
    let text = Text("abcdefghijklmnop").wrapping()
    let proposal = Size(width: 96, height: 100)
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    #expect(measureBlock(text, proposal: proposal, context: context).height == 64)
    context.fontMetrics.lineAdvance = 40
    #expect(measureBlock(text, proposal: proposal, context: context).height == 80)
    #expect(PipelineMetrics.snapshot.textLayouts == 1)
    context.fontMetrics.cellAdvance = 24
    #expect(measureBlock(text, proposal: proposal, context: context).height == 160)
    #expect(PipelineMetrics.snapshot.textLayouts == 2)
    context.textScale = 2
    #expect(measureBlock(text, proposal: proposal, context: context).height == 640)
    #expect(PipelineMetrics.snapshot.textLayouts == 3)
  }

  @Test func replacingTheRootReleasesCachedText() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.setContent(Text("old"))
    _ = runtime.render(viewport: Size(width: 200, height: 100), input: InputState(), onChange: {})
    #expect(runtime.interaction.textLayouts.count == 1)
    weak let old = runtime.interaction.textLayouts.resolve("old", columns: nil)
    runtime.setContent(Text("new"))
    #expect(runtime.interaction.textLayouts.count == 0)
    #expect(old == nil)
  }

  @MainActor private final class EditorState {
    var version = 1
    var changes: [Int] = []
  }

  @Test func cachedTextKeepsFreshEditorCallbacksBetweenInputs() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let focus = FocusTarget()
    let state = EditorState()
    runtime.setContent(
      DeferredBlock {
        let captured = state.version
        return TextEditor(text: { "same" }, onChange: { _ in state.changes.append(captured) }).focusTarget(focus)
      })
    _ = runtime.render(viewport: Size(width: 200, height: 100), input: InputState(), onChange: {})
    focus.focus(editing: true)
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    runtime.handleInput(InputState(textEvents: [.insert("a")]))
    state.version = 2
    runtime.handleInput(InputState(textEvents: [.insert("b")]))
    #expect(state.changes == [1, 2])
    #expect(PipelineMetrics.snapshot.textLayouts == 0)
    #expect(PipelineMetrics.snapshot.paints == 0)
  }
}
