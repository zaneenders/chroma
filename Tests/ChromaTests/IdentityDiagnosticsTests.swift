import Testing

@testable import Chroma

struct IdentityDiagnosticsTests {
  private struct Item: Identifiable {
    let id: Int
  }

  @MainActor private static func draw(_ build: LayoutBuilder, context: LayoutContext = LayoutContext()) {
    beginTestFrame(context.interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = build(&resolvedBuffer, context)
      resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 100))
      resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 100))
    }
    context.interaction.endFrame()
  }

  @Test func duplicateDirectLeafKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        let context = LayoutContext()
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
    let context = LayoutContext()
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

  @Test func duplicateIdentifiableKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        Self.draw { buffer, context in
          let children = [Item(id: 1), Item(id: 1)].map { item in
            buffer.text(Text("Row"), context: context.keyed(item.id))
          }
          return buffer.stack(children, axis: .vertical, context: context)
        }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate interaction leaf ID"))
  }

  @Test func duplicateKeyPathCollectionKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        Self.draw { buffer, context in
          let children = [1, 1].map { id in buffer.text(Text("Row"), context: context.keyed(id)) }
          return buffer.stack(children, axis: .vertical, context: context)
        }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate interaction leaf ID"))
  }

  @Test func duplicateLazyDataKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        _ = ScrollView(
          data: [Item(id: 1), Item(id: 1)], rowHeight: 20,
          controller: ScrollViewController()
        ) { buffer, context, _ in buffer.text(Text("Row"), context: context) }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate lazy collection element ID"))
  }

  @Test func distinctLazyRowKeyTypesSucceed() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        Self.draw { buffer, context in
          buffer.scrollView(
            ScrollView(
              controller: ScrollViewController(),
              rows: [
                .init(id: Int(1)) { buffer, context in buffer.text(Text("Int"), context: context) },
                .init(id: Int64(1)) { buffer, context in buffer.text(Text("Int64"), context: context) },
              ]), context: context)
        }
      }
    }
  }

  @Test func duplicateLazyRowKeysFail() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        Self.draw { buffer, context in
          buffer.scrollView(
            ScrollView(
              controller: ScrollViewController(),
              rows: [
                .init(id: 1) { buffer, context in buffer.text(Text("First"), context: context) },
                .init(id: 1) { buffer, context in buffer.text(Text("Second"), context: context) },
              ]), context: context)
        }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("Duplicate lazy row ID"))
  }

  @Test func sharedFocusTargetAcrossControlsFails() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        let target = FocusTarget()
        Self.draw { buffer, context in
          let first = buffer.focus(target, context: context.childScope(0)) { buffer, context in
            buffer.button(Button("First") {}, context: context)
          }
          let second = buffer.focus(target, context: context.childScope(1)) { buffer, context in
            buffer.button(Button("Second") {}, context: context)
          }
          return buffer.stack([first, second], axis: .vertical, context: context)
        }
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("FocusTarget must bind to exactly one control"))
  }

  @Test func sharedFocusTargetAcrossInteractionInstancesFails() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
      await MainActor.run {
        let target = FocusTarget()
        let first = LayoutContext()
        let second = LayoutContext()
        Self.draw(
          { buffer, context in
            buffer.focus(target, context: context) { buffer, context in
              buffer.button(Button("First") {}, context: context)
            }
          }, context: first)
        Self.draw(
          { buffer, context in
            buffer.focus(target, context: context) { buffer, context in
              buffer.button(Button("Second") {}, context: context)
            }
          }, context: second)
        withExtendedLifetime(first) {}
      }
    }
    let diagnostic = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(diagnostic.contains("FocusTarget cannot be bound to multiple interaction instances"))
  }
}
