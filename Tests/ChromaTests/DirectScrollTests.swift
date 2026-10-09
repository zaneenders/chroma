import ChromaTesting
import Synchronization
import Testing

@testable import Chroma

@MainActor
struct DirectScrollTests {
  private struct Item: Identifiable {
    let id: Int
    var value = 0
  }

  @MainActor private final class Harness {
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    let rect = Rect(x: 0, y: 0, width: 120, height: 60)

    @discardableResult func render(_ build: LayoutBuilder) -> [DrawEntry] {
      buffer.reset()
      context.interaction.viewport = rect
      context.interaction.beginFrame(input: InputState())
      let root = build(&buffer, context)
      buffer.register(root, in: rect)
      var list = DrawList()
      buffer.paint(root, into: &list, in: rect)
      context.interaction.endFrame()
      return list.commands
    }
  }

  @Test func normalDirectScrollMatchesRetainedConfiguration() {
    let direct = Harness()
    let retained = Harness()
    let directController = ScrollViewController()
    let retainedController = ScrollViewController()
    let directBuild: LayoutBuilder = { buffer, context in
      buffer.scrollView(
        ScrollView(
          controller: directController,
          build: { buffer, context in
            let fill = buffer.color(.white, context: context)
            return buffer.sizing(fill, x: .fixed(300), y: .fixed(600), context: context)
          }), context: context)
    }
    let retainedScroll = ScrollView(
      controller: retainedController,
      build: { buffer, context in
        let child = buffer.sizing(
          buffer.color(.white, context: context.childScope(0)), x: .fixed(300), y: .fixed(600),
          context: context.childScope(0))
        return buffer.stack([child], axis: .vertical, context: context)
      })
    let retainedBuild: LayoutBuilder = { buffer, context in
      buffer.scrollView(retainedScroll, context: context)
    }
    #expect(direct.render(directBuild) == retained.render(retainedBuild))
    directController.scroll(to: 150)
    retainedController.scroll(to: 150)
    #expect(direct.render(directBuild) == retained.render(retainedBuild))
    #expect(directController.offset == 150)
    #expect(directController.offset == retainedController.offset)
  }

  @Test func identifiedRowsUseKeyedPlacementAndExactScrollOffsets() {
    @MainActor final class PlacedRows {
      var built: [Int] = []
      var rects: [Int: Rect] = [:]
    }
    let placed = PlacedRows()
    let h = Harness()
    let controller = ScrollViewController()
    let scroll = ScrollView(
      data: (0..<100).map { Item(id: $0) }, rowHeight: 20, controller: controller,
      build: { buffer, context, item in
        placed.built.append(item.id)
        return buffer.customLeaf(
          context: context, focusRule: .standard,
          measure: { Size(width: $0.width, height: 20) },
          register: { placed.rects[item.id] = $0 },
          paint: { list, rect in list.fillRect(rect, color: .white) })
      })
    let build: LayoutBuilder = { buffer, context in buffer.scrollView(scroll, context: context) }
    h.render(build)
    #expect(placed.built == [0, 1, 2, 3])
    #expect(
      placed.rects == [
        0: Rect(x: 0, y: 0, width: 120, height: 20),
        1: Rect(x: 0, y: 20, width: 120, height: 20),
        2: Rect(x: 0, y: 40, width: 120, height: 20),
        3: Rect(x: 0, y: 60, width: 120, height: 20),
      ])
    #expect(controller.uniformRowIdentity?.indices[StructuralKey(50)] == 50)
    placed.built = []
    placed.rects = [:]
    controller.scrollToRow(50)
    h.render(build)
    #expect(controller.offset == 1000)
    #expect(placed.built == [49, 50, 51, 52, 53])
    #expect(
      placed.rects == [
        49: Rect(x: 0, y: -20, width: 120, height: 20),
        50: Rect(x: 0, y: 0, width: 120, height: 20),
        51: Rect(x: 0, y: 20, width: 120, height: 20),
        52: Rect(x: 0, y: 40, width: 120, height: 20),
        53: Rect(x: 0, y: 60, width: 120, height: 20),
      ])
  }

  @Test func identifiedConstructorWinsWithoutAnExplicitRevision() {
    let items = [Item(id: 10), Item(id: 20)]
    let controller = ScrollViewController()
    let scroll = ScrollView(
      data: items, rowHeight: 20, controller: controller,
      build: { buffer, context, item in
        buffer.text(Text("\(item.id)"), context: context)
      })
    #expect(controller.uniformRowIdentity?.indices[StructuralKey(20)] == 1)
    let h = Harness()
    h.render { buffer, context in buffer.scrollView(scroll, context: context) }
    #expect(controller.uniformRowIdentity?.indices[StructuralKey(20)] == 1)
  }

  @Test func positionalRowsBuildOnlyTheVisibleWindowInTheirFinalContext() {
    @MainActor final class Built { var indices: [Int] = [] }
    let built = Built()
    let controller = ScrollViewController()
    let h = Harness()
    let build: LayoutBuilder = { buffer, context in
      buffer.scrollView(
        ScrollView(
          data: 0..<100_000, rowHeight: 20, controller: controller,
          build: {
            buffer, context, index in
            #expect(context.focusLeafClaimed)
            built.indices.append(index)
            return buffer.text(Text("\(index)"), context: context)
          }), context: context)
    }
    h.render(build)
    #expect(built.indices == [0, 1, 2, 3])
    #expect(controller.uniformRowIdentity == nil)
    built.indices = []
    controller.scroll(to: 1000)
    h.render(build)
    #expect(built.indices == [49, 50, 51, 52, 53])
    #expect(h.buffer.count < 20)
  }

  @Test func replacingVariableRowBuildInvalidatesItsMeasurement() {
    let controller = ScrollViewController()
    let h = Harness()
    func row(_ id: Int, height: Float) -> ScrollView.Row {
      ScrollView.Row(
        id: id,
        build: { buffer, context in
          let fill = buffer.color(.white, context: context)
          return buffer.sizing(fill, y: .fixed(height), context: context)
        })
    }
    var rows = [row(0, height: 10), row(1, height: 10)]
    h.render { buffer, context in buffer.scrollView(ScrollView(controller: controller, rows: rows), context: context) }
    let old = controller.lazyStackCache.measurements[0]
    rows[0].build = row(0, height: 30).build
    h.render { buffer, context in buffer.scrollView(ScrollView(controller: controller, rows: rows), context: context) }
    #expect(controller.lazyStackCache.rowSizes.map(\.height) == [30, 10])
    #expect(controller.lazyStackCache.measurements[0] !== old)
    #expect(controller.measurementBuffer.count == 0)
  }

  @Test func variableRowsKeepMeasurementStorageBoundedAsTheDatasetGrows() {
    let controller = ScrollViewController()
    let h = Harness()
    func rows(_ count: Int) -> [ScrollView.Row] {
      (0..<count).map { id in
        ScrollView.Row(
          id: id,
          build: { buffer, context in
            let fill = buffer.color(.white, context: context)
            return buffer.sizing(fill, y: .fixed(10), context: context)
          })
      }
    }
    h.render { buffer, context in
      buffer.scrollView(ScrollView(controller: controller, rows: rows(100)), context: context)
    }
    let capacity = controller.measurementBuffer.capacity
    h.render { buffer, context in
      buffer.scrollView(ScrollView(controller: controller, rows: rows(1000)), context: context)
    }
    #expect(controller.measurementBuffer.count == 0)
    #expect(controller.measurementBuffer.capacity == capacity)
    #expect(h.buffer.count < 30)
  }

  private final class CountedRowID: Hashable, Sendable {
    let value: Int
    let hashCount = Mutex(0)

    init(_ value: Int) { self.value = value }
    static func == (lhs: CountedRowID, rhs: CountedRowID) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) {
      hashCount.withLock { $0 += 1 }
      hasher.combine(value)
    }
  }

  @Test func unchangedVariableRowsSkipDuplicateKeyHashing() {
    let controller = ScrollViewController()
    let h = Harness()
    let ids = (0..<10).map { CountedRowID($0) }
    let rows = ids.map { id in
      ScrollView.Row(
        id: id,
        build: { buffer, context in
          buffer.sizing(buffer.color(.white, context: context), y: .fixed(20), context: context)
        })
    }
    let build: LayoutBuilder = { buffer, context in
      buffer.scrollView(ScrollView(controller: controller, rows: rows), context: context)
    }
    h.render(build)
    let offscreenID = ids.last!
    #expect(offscreenID.hashCount.withLock { $0 } > 0)
    offscreenID.hashCount.withLock { $0 = 0 }
    let measurements = controller.lazyStackCache.measurements

    h.render(build)
    #expect(offscreenID.hashCount.withLock { $0 } == 0)
    #expect(zip(measurements, controller.lazyStackCache.measurements).allSatisfy { $0 === $1 })
  }

  @Test func revisionReuseKeepsCurrentRowValuesAndActions() {
    @MainActor final class Model {
      var value = 1
      var label = "old"
      var actions: [String] = []
    }
    let model = Model()
    let controller = ScrollViewController()
    let host = HeadlessHost(size: Size(width: 200, height: 100))
    defer { host.close() }
    host.build = { buffer, context in
      let label = model.label
      return buffer.scrollView(
        ScrollView(
          data: [Item(id: 1, value: model.value)], rowHeight: 40,
          controller: controller, identityRevision: 1,
          build: { buffer, context, item in
            buffer.button(Button(label) { model.actions.append("\(item.value):\(label)") }, context: context)
          }), context: context)
    }
    host.render()
    host.interaction.focusFirstControlForTest()
    let identity = controller.uniformRowIdentity
    model.value = 10
    model.label = "new"
    host.sendInput(InputState(commands: [.action(.activate)]))
    #expect(model.actions == ["10:new"])
    #expect(controller.uniformRowIdentity === identity)
  }

  @Test func directLogicalSelectionUsesUpdatedIdentityOrder() {
    @MainActor final class Model {
      var items = [Item(id: 0), Item(id: 1), Item(id: 2)]
      var revision: UInt64 = 1
    }
    let model = Model()
    let controller = ScrollViewController()
    let selection = ScrollSelection<Int>()
    let host = HeadlessHost(size: Size(width: 200, height: 100))
    defer { host.close() }
    host.build = { buffer, context in
      buffer.scrollView(
        ScrollView(
          data: model.items, rowHeight: 20, controller: controller, selection: selection,
          identityRevision: model.revision,
          build: { buffer, context, item in
            buffer.text(Text("Row \(item.id)"), context: context)
          }), context: context)
    }
    host.render()
    host.render(input: InputState(commands: [.navigation(.down), .navigation(.stepIn), .navigation(.down)]))
    #expect(selection.selectedID == 1)
    model.items = [Item(id: 0), Item(id: 1), Item(id: 3)]
    model.revision = 2
    host.render(input: InputState(commands: [.navigation(.down)]))
    #expect(selection.selectedID == 3)
  }

  @Test func virtualizingAnEditorEndsEditingWithoutKeepingStaleCallbacks() throws {
    @MainActor final class Model {
      var items = (0..<100).map { Item(id: $0) }
      var revision: UInt64 = 1
      var text = "edit"
      var changes = 0
      var textEvents = 0
    }
    let model = Model()
    let controller = ScrollViewController()
    let editor = FocusTarget()
    let host = HeadlessHost(size: Size(width: 200, height: 60))
    defer { host.close() }
    host.build = { buffer, context in
      buffer.scrollView(
        ScrollView(
          data: model.items, rowHeight: 20, controller: controller, identityRevision: model.revision,
          build: { buffer, context, item in
            guard item.id == 0 else { return buffer.text(Text("Row \(item.id)"), context: context) }
            return buffer.focus(editor, context: context) { buffer, context in
              buffer.textEditor(
                TextEditor(
                  padding: 0, singleLine: true, text: { model.text },
                  onChange: {
                    model.text = $0
                    model.changes += 1
                  },
                  onTextEvent: { _, _ in
                    model.textEvents += 1
                    return nil
                  }), context: context)
            }
          }), context: context)
    }
    host.render()
    editor.focus(editing: true)
    host.render()
    host.render(input: InputState(textEvents: [.selectAll]))
    let interaction = host.runtime.interaction
    let editingID = try #require(editor.boundID)
    #expect(interaction.editingLeaf == editingID)
    #expect(editor.isEditing)
    #expect(interaction.textSelectionRange == 0..<4)
    let eventCount = model.textEvents

    controller.scroll(to: 1000)
    host.render()
    #expect(controller.offset == 1000)
    #expect(interaction.tree?.findLeaf(editingID) == nil)
    #expect(interaction.editingLeaf == nil)
    #expect(!interaction.isTextEditing)
    #expect(interaction.textSelectionRange == nil)
    #expect(interaction.editingText == nil)
    #expect(interaction.scrollStates.values.first!.rows.count < 10)
    host.render(input: InputState(textEvents: [.insert("stale")]))
    #expect(model.textEvents == eventCount)
    #expect(model.changes == 0)
    #expect(model.text == "edit")

    controller.scrollToTop()
    host.render()
    #expect(editor.boundID == editingID)
    #expect(!editor.isEditing)
    #expect(interaction.editingLeaf == nil)
    #expect(interaction.textSelectionRange == nil)
    model.items.removeFirst()
    model.revision += 1
    host.render()
    host.render(input: InputState(textEvents: [.insert("removed")]))
    #expect(interaction.tree?.findLeaf(editingID) == nil)
    #expect(interaction.editingLeaf == nil)
    #expect(interaction.textSelectionRange == nil)
    #expect(model.textEvents == eventCount)
    #expect(model.changes == 0)
  }

}
