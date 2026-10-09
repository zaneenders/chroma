import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct DirectScrollTests {
  private struct Item: Identifiable {
    let id: Int
    var value = 0
  }

  @MainActor private final class Harness {
    let context = BlockContext()
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

  @Test func normalDirectScrollMatchesBlockConvenience() {
    let direct = Harness()
    let blocks = Harness()
    let directController = ScrollViewController()
    let blockController = ScrollViewController()
    let directBuild: LayoutBuilder = { buffer, context in
      buffer.scrollView(controller: directController, context: context) { buffer, context in
        let fill = buffer.color(.white, context: context)
        return buffer.sizing(fill, x: .fixed(300), y: .fixed(600), context: context)
      }
    }
    let blockBuild: LayoutBuilder = { buffer, context in
      buffer.emit(
        ScrollView(controller: blockController) {
          Color.white.sizing(x: .fixed(300), y: .fixed(600))
        }, context: context)
    }
    #expect(direct.render(directBuild) == blocks.render(blockBuild))
    directController.scroll(to: 150)
    blockController.scroll(to: 150)
    #expect(direct.render(directBuild) == blocks.render(blockBuild))
    #expect(directController.offset == 150)
    #expect(directController.offset == blockController.offset)
  }

  @Test func identifiedDirectScrollMatchesBlockConvenience() {
    let direct = Harness()
    let blocks = Harness()
    let directController = ScrollViewController()
    let blockController = ScrollViewController()
    let items = (0..<100).map { Item(id: $0) }
    let directBuild: LayoutBuilder = { buffer, context in
      buffer.scrollView(data: items, rowHeight: 20, controller: directController, context: context) {
        buffer, context, item in
        buffer.text(Text("Row \(item.id)"), context: context)
      }
    }
    let blockBuild: LayoutBuilder = { buffer, context in
      buffer.emit(
        ScrollView(data: items, rowHeight: 20, controller: blockController) { Text("Row \($0.id)") },
        context: context)
    }
    #expect(direct.render(directBuild) == blocks.render(blockBuild))
    #expect(directController.uniformRowIdentity?.keys == blockController.uniformRowIdentity?.keys)
    directController.scrollToRow(50)
    blockController.scrollToRow(50)
    #expect(direct.render(directBuild) == blocks.render(blockBuild))
    #expect(directController.offset == blockController.offset)
    #expect(directController.offset > 0)
  }

  @Test func identifiedOverloadsWinWithoutAnExplicitRevision() {
    let items = [Item(id: 10), Item(id: 20)]
    let controller = ScrollViewController()
    _ = ScrollView(
      data: items, rowHeight: 20, controller: controller,
      build: { buffer, context, item in
        buffer.text(Text("\(item.id)"), context: context)
      })
    #expect(controller.uniformRowIdentity?.indices[StructuralKey(20)] == 1)
    let directController = ScrollViewController()
    let h = Harness()
    h.render { buffer, context in
      buffer.scrollView(data: items, rowHeight: 20, controller: directController, context: context) {
        buffer, context, item in
        buffer.text(Text("\(item.id)"), context: context)
      }
    }
    #expect(directController.uniformRowIdentity?.indices[StructuralKey(20)] == 1)
  }

  @Test func positionalRowsBuildOnlyTheVisibleWindowInTheirFinalContext() {
    @MainActor final class Built { var indices: [Int] = [] }
    let built = Built()
    let controller = ScrollViewController()
    let h = Harness()
    let build: LayoutBuilder = { buffer, context in
      buffer.scrollView(data: 0..<100_000, rowHeight: 20, controller: controller, context: context) {
        buffer, context, index in
        #expect(context.focusLeafClaimed)
        built.indices.append(index)
        return buffer.text(Text("\(index)"), context: context)
      }
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
    h.render { buffer, context in buffer.scrollView(controller: controller, rows: rows, context: context) }
    let old = controller.lazyStackCache.measurements[0]
    rows[0].build = row(0, height: 30).build
    h.render { buffer, context in buffer.scrollView(controller: controller, rows: rows, context: context) }
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
    h.render { buffer, context in buffer.scrollView(controller: controller, rows: rows(100), context: context) }
    let capacity = controller.measurementBuffer.capacity
    h.render { buffer, context in buffer.scrollView(controller: controller, rows: rows(1000), context: context) }
    #expect(controller.measurementBuffer.count == 0)
    #expect(controller.measurementBuffer.capacity == capacity)
    #expect(h.buffer.count < 30)
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
        data: [Item(id: 1, value: model.value)], rowHeight: 40,
        controller: controller, identityRevision: 1, context: context
      ) { buffer, context, item in
        buffer.button(Button(label) { model.actions.append("\(item.value):\(label)") }, context: context)
      }
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
        data: model.items, rowHeight: 20, controller: controller, selection: selection,
        identityRevision: model.revision, context: context
      ) { buffer, context, item in
        buffer.text(Text("Row \(item.id)"), context: context)
      }
    }
    host.render()
    host.render(input: InputState(commands: [.navigation(.down), .navigation(.stepIn), .navigation(.down)]))
    #expect(selection.selectedID == 1)
    model.items = [Item(id: 0), Item(id: 1), Item(id: 3)]
    model.revision = 2
    host.render(input: InputState(commands: [.navigation(.down)]))
    #expect(selection.selectedID == 3)
  }
}
