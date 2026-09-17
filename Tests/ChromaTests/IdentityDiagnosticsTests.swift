import Testing

@testable import Chroma

struct IdentityDiagnosticsTests {
  private struct Item: Identifiable {
    let id: Int
  }

  @MainActor private static func draw(_ block: any Block, context: RenderContext = RenderContext()) {
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(block, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 100), context: context)
    context.interaction.endFrame()
  }

  @Test func duplicateForEachKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        _ = ForEach([Item(id: 1), Item(id: 1)]) { _ in Text("Row") }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate collection element ID: 1"))
  }

  @Test func duplicateLazyDataKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        _ = LazyVStack(
          data: [Item(id: 1), Item(id: 1)], rowHeight: 20,
          controller: ScrollViewController()
        ) { _ in Text("Row") }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate lazy collection element ID"))
  }

  @Test func duplicateLazyRowKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        Self.draw(
          LazyVStack(
            controller: ScrollViewController(),
            rows: [
              .init(id: 1, content: Text("First")),
              .init(id: 1, content: Text("Second")),
            ]))
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate lazy row ID"))
  }

  @Test func sharedFocusTargetAcrossControlsFails() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        let target = FocusTarget()
        Self.draw(
          VStack {
            Button("First") {}.focusTarget(target)
            Button("Second") {}.focusTarget(target)
          })
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("FocusTarget must bind to exactly one control"))
  }

  @Test func sharedFocusTargetAcrossInteractionInstancesFails() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        let target = FocusTarget()
        let first = RenderContext()
        let second = RenderContext()
        Self.draw(Button("First") {}.focusTarget(target), context: first)
        Self.draw(Button("Second") {}.focusTarget(target), context: second)
        withExtendedLifetime(first) {}
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("FocusTarget cannot be bound to multiple interaction instances"))
  }
}
