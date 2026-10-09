import Testing

@testable import Chroma

struct IdentityDiagnosticsTests {
  private struct Item: Identifiable {
    let id: Int
  }

  @MainActor private static func draw(_ block: any Block, context: BlockContext = BlockContext()) {
    beginTestFrame(context.interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(block, context: context)
      resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 100))
      resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 100))
    }
    context.interaction.endFrame()
  }

  @Test func duplicateDirectLeafKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        let context = BlockContext()
        var buffer = LayoutBuffer()
        let first = buffer.text(Text("first"), context: context.keyed("same"))
        let second = buffer.text(Text("second"), context: context.keyed("same"))
        let root = buffer.stack([first, second], axis: .vertical, context: context)
        beginTestFrame(context.interaction, input: InputState())
        buffer.register(root, in: Rect(x: 0, y: 0, width: 100, height: 100))
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate interaction leaf ID"))
  }

  @MainActor @Test func matchingChildKeysInDifferentParentsRemainDistinctAcrossUpdates() {
    let context = BlockContext()
    var buffer = LayoutBuffer()
    for _ in 0..<2 {
      buffer.reset()
      let first = buffer.text(Text("first"), context: context.keyed("left").keyed("child"))
      let second = buffer.text(Text("second"), context: context.keyed("right").keyed("child"))
      let root = buffer.stack([first, second], axis: .vertical, context: context)
      beginTestFrame(context.interaction, input: InputState())
      buffer.register(root, in: Rect(x: 0, y: 0, width: 100, height: 100))
      context.interaction.endFrame()
      let children = context.interaction.tree?.children.first?.children
      #expect(children?.count == 2)
      #expect(children?.first?.leafID != children?.last?.leafID)
    }
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

  @Test func duplicateKeyPathCollectionKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        _ = ForEach([1, 1], id: \.self) { _ in Text("Row") }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate collection element ID: 1"))
  }

  @Test func duplicateLazyDataKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        _ = ScrollView(
          data: [Item(id: 1), Item(id: 1)], rowHeight: 20,
          controller: ScrollViewController()
        ) { _ in Text("Row") }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate lazy collection element ID"))
  }

  @Test func distinctLazyRowKeyTypesSucceed() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        Self.draw(
          ScrollView(
            controller: ScrollViewController(),
            rows: [
              .init(id: Int(1), content: Text("Int")),
              .init(id: Int64(1), content: Text("Int64")),
            ]))
      }
    }
  }

  @Test func duplicateLazyRowKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        Self.draw(
          ScrollView(
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
        let first = BlockContext()
        let second = BlockContext()
        Self.draw(Button("First") {}.focusTarget(target), context: first)
        Self.draw(Button("Second") {}.focusTarget(target), context: second)
        withExtendedLifetime(first) {}
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("FocusTarget cannot be bound to multiple interaction instances"))
  }
}
