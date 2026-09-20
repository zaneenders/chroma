import Testing

@testable import Chroma

@MainActor
struct StructuralPathTests {
  private final class Recorder {
    var measured: [String: StructuralPath] = [:]
    var drawn: [String: StructuralPath] = [:]
  }

  private struct Probe: PrimitiveBlock {
    let name: String
    let recorder: Recorder

    var focusRule: FocusRule { .standard }

    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
      recorder.measured[name] = context.structuralPath
      return Size(width: 10, height: 10)
    }

    func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
      recorder.drawn[name] = context.structuralPath
    }
  }

  private struct Component: Block {
    let name: String
    let recorder: Recorder
    var body: some Block { Probe(name: name, recorder: recorder) }
  }

  private func render(_ block: any Block, recorder: Recorder) -> [String: StructuralPath] {
    let context = RenderContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    recorder.measured = [:]
    recorder.drawn = [:]
    _ = BlockEngine.measure(block, proposal: rect.size, context: context)
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(block, into: &list, in: rect, context: context)
    context.interaction.endFrame()
    #expect(recorder.measured == recorder.drawn)
    return recorder.drawn
  }

  @Test func explicitKeysAreParentScopedTypeSensitiveAndPreserveCollectionLayout() {
    let recorder = Recorder()
    func content(_ key: some Hashable & Sendable) -> VStack {
      VStack {
        ForEach([1, 2], id: \.self) { value in
          Probe(name: "row\(value)", recorder: recorder)
        }.id(key).padding(0)
        Probe(name: "sibling", recorder: recorder).id(key)
      }
    }
    let first = render(content(1), recorder: recorder)
    #expect(first == render(content(1), recorder: recorder))
    let changed = render(content("1"), recorder: recorder)
    #expect(first["row1"] != changed["row1"])
    #expect(first["row1"] != first["row2"])
    #expect(first["row1"] != first["sibling"])
    let size = BlockEngine.measure(
      content(1), proposal: Size(width: 100, height: 100), context: RenderContext())
    #expect(size.height == 30)
  }

  @Test func optionalAndBranchesPreserveSiblingSlots() {
    let recorder = Recorder()
    func content(_ flag: Bool) -> VStack {
      VStack {
        if flag { Probe(name: "optional", recorder: recorder) }
        if flag {
          Probe(name: "branch", recorder: recorder)
        } else {
          Probe(name: "branch", recorder: recorder)
        }
        Probe(name: "sibling", recorder: recorder)
      }
    }
    let first = render(content(true), recorder: recorder)
    let second = render(content(false), recorder: recorder)
    #expect(first["sibling"] == second["sibling"])
    #expect(first["branch"] != second["branch"])
    #expect(first == render(content(true), recorder: recorder))
  }

  @Test func repeatedComponentsAndReversedLayout() {
    let recorder = Recorder()
    let stack = HStack {
      Component(name: "first", recorder: recorder)
      Component(name: "second", recorder: recorder)
    }
    let first = render(stack, recorder: recorder)
    #expect(first["first"] != first["second"])
    #expect(first == render(stack.reverseLayout(), recorder: recorder))
  }

  @Test func nestedTuplesAndRawChildren() {
    let recorder = Recorder()
    let nested = BlockBuilder.buildBlock(
      Probe(name: "first", recorder: recorder),
      BlockBuilder.buildBlock(Probe(name: "second", recorder: recorder)))
    #expect(nested.children.count == 2)
    let first = render(nested, recorder: recorder)
    #expect(first["first"] != first["second"])
    let replaced = TupleBlock(children: [
      Probe(name: "third", recorder: recorder),
      Probe(name: "fourth", recorder: recorder),
    ])
    let second = render(replaced, recorder: recorder)
    #expect(second["third"] != second["fourth"])
    #expect(first == render(nested, recorder: recorder))
  }

  @Test func containerChildrenAreReadOnly() {
    func expectReadOnly<Container>(_ keyPath: KeyPath<Container, [any Block]>) {
      #expect(!(keyPath is WritableKeyPath<Container, [any Block]>))
    }
    expectReadOnly(\HStack.children)
    expectReadOnly(\VStack.children)
    expectReadOnly(\ZStack.children)
    expectReadOnly(\TupleBlock.children)
  }

  private struct Pair: PrimitiveBlock {
    let recorder: Recorder

    var focusRule: FocusRule { .container }

    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
      _ = BlockEngine.measure(
        Probe(name: "first", recorder: recorder), proposal: proposal, context: context.childScope(0))
      return BlockEngine.measure(
        Probe(name: "second", recorder: recorder), proposal: proposal, context: context.childScope(1))
    }

    func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
      BlockEngine.draw(
        Probe(name: "second", recorder: recorder), into: &drawList, in: rect, context: context.childScope(1))
      BlockEngine.draw(
        Probe(name: "first", recorder: recorder), into: &drawList, in: rect, context: context.childScope(0))
    }
  }

  @Test func customContainerSlotsDoNotDependOnTraversalOrder() {
    let recorder = Recorder()
    let paths = render(Pair(recorder: recorder), recorder: recorder)
    #expect(paths["first"] != paths["second"])
    #expect(paths == render(Pair(recorder: recorder), recorder: recorder))
  }

  @Test func stylingModifiersAreTransparent() {
    let recorder = Recorder()
    let probe = Probe(name: "content", recorder: recorder)
    let expected = render(probe, recorder: recorder)
    let styled = probe.padding(4).sizing(x: .grow).border(.white)
      .roundedBackground(.white, radius: 2).clipped().background(Color.white)
    #expect(render(styled, recorder: recorder) == expected)
    #expect(render(styled.padding(12).background(Color.white), recorder: recorder) == expected)
    let component = Component(name: "content", recorder: recorder)
    #expect(render(component, recorder: recorder) != expected)
    let componentPath = render(component, recorder: recorder)
    #expect(render(component.padding(4), recorder: recorder) == componentPath)
  }

  @Test func backgroundLayersHaveDistinctScopes() {
    let recorder = Recorder()
    let probe = Probe(name: "content", recorder: recorder)
    let expected = render(probe, recorder: recorder)["content"]
    let layered = probe.background(Probe(name: "inner", recorder: recorder))
      .background(Probe(name: "outer", recorder: recorder))
    let context = RenderContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    func draw() -> [String: StructuralPath] {
      recorder.drawn = [:]
      var list = DrawList()
      BlockEngine.draw(layered, into: &list, in: rect, context: context)
      return recorder.drawn
    }
    let paths = draw()
    #expect(paths["content"] == expected)
    #expect(Set(paths.values).count == 3)
    #expect(draw() == paths)
    recorder.measured = [:]
    _ = BlockEngine.measure(layered, proposal: rect.size, context: context)
    #expect(recorder.measured["content"] == expected)
  }

  private struct Item: Identifiable {
    let id: Int
  }

  @Test func keyedCollectionsPreserveItemsAndSiblingSlots() {
    let recorder = Recorder()
    func content(_ ids: [Int]) -> VStack {
      VStack(spacing: 3) {
        ForEach(ids.map { Item(id: $0) }) { item in
          Probe(name: String(item.id), recorder: recorder)
        }
        Probe(name: "sibling", recorder: recorder)
      }
    }
    let before = render(content([1, 2, 3]), recorder: recorder)
    let after = render(content([3, 4, 1]), recorder: recorder)
    #expect(before["1"] == after["1"])
    #expect(before["3"] == after["3"])
    #expect(before["sibling"] == after["sibling"])
    #expect(Set(after.values).count == 4)
    #expect(render(content([]), recorder: recorder)["sibling"] == before["sibling"])
    #expect(
      BlockEngine.measure(
        content([1, 2]), proposal: Size(width: 100, height: 100),
        context: RenderContext()) == Size(width: 10, height: 36))
  }

  @Test(arguments: ["vertical", "horizontal", "overlay"])
  func modifiedCollectionsPreserveLayoutAndPaths(axis: String) {
    let recorder = Recorder()
    func content(_ modified: Bool, ids: [Int]) -> any Block {
      let collection = ForEach(ids.map { Item(id: $0) }) { item in
        Probe(name: String(item.id), recorder: recorder)
        Probe(name: "extra-\(item.id)", recorder: recorder)
      }
      let child: any Block =
        modified
        ? collection.padding(0).border(.white).clipped().background(Color.white)
        : collection
      switch axis {
      case "vertical":
        return VStack(spacing: 3) {
          child
          Probe(name: "sibling", recorder: recorder)
        }
      case "horizontal":
        return HStack(spacing: 3) {
          child
          Probe(name: "sibling", recorder: recorder)
        }
      default:
        return ZStack {
          child
          Probe(name: "sibling", recorder: recorder)
        }
      }
    }
    let proposal = Size(width: 100, height: 100)
    let plain = content(false, ids: [1, 2])
    let styled = content(true, ids: [1, 2])
    let paths = render(plain, recorder: recorder)
    #expect(render(styled, recorder: recorder) == paths)
    #expect(
      BlockEngine.measure(plain, proposal: proposal, context: RenderContext())
        == BlockEngine.measure(styled, proposal: proposal, context: RenderContext()))
    let reordered = render(content(true, ids: [2, 3, 1]), recorder: recorder)
    for (name, path) in paths { #expect(reordered[name] == path) }
    #expect(render(content(true, ids: []), recorder: recorder)["sibling"] == paths["sibling"])
  }

  @Test func collectionPaddingAppliesToEachChild() {
    let recorder = Recorder()
    let block = VStack(spacing: 3) {
      ForEach([Item(id: 1), Item(id: 2)]) { item in
        Probe(name: String(item.id), recorder: recorder)
      }.padding(2)
    }
    #expect(
      BlockEngine.measure(block, proposal: Size(width: 100, height: 100), context: RenderContext())
        == Size(width: 14, height: 31))
  }

  @Test func collectionKeysAreParentScopedAndTypeSensitive() {
    let recorder = Recorder()
    let paths = render(
      HStack {
        ForEach([Item(id: 1)]) { _ in Probe(name: "first", recorder: recorder) }
        ForEach([Item(id: 1)]) { _ in Probe(name: "second", recorder: recorder) }
      }, recorder: recorder)
    #expect(paths["first"] != paths["second"])
    #expect(StructuralKey(1) != StructuralKey(Int64(1)))
    #expect(StructuralKey(1) == StructuralKey(1))
  }

  @Test(arguments: [false, true])
  func lazyRowsFollowKeysAcrossReordering(uniform: Bool) {
    let recorder = Recorder()
    let controller = ScrollViewController()
    let context = RenderContext()
    func draw(_ ids: [Int]) -> [String: StructuralPath] {
      recorder.measured = [:]
      recorder.drawn = [:]
      let stack: LazyVStack
      if uniform {
        stack = LazyVStack(
          id: WidgetID("list"), data: ids.map { Item(id: $0) },
          rowHeight: 10, controller: controller
        ) { item in
          Probe(name: String(item.id), recorder: recorder)
        }
      } else {
        stack = LazyVStack(
          id: WidgetID("list"), controller: controller,
          rows: ids.map { .init(id: WidgetID(String($0)), content: Probe(name: String($0), recorder: recorder)) })
      }
      context.interaction.beginFrame(input: InputState())
      var list = DrawList()
      BlockEngine.draw(stack, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 100), context: context)
      context.interaction.endFrame()
      if !uniform { #expect(recorder.measured == recorder.drawn) }
      return recorder.drawn
    }
    let before = draw([1, 2, 3])
    let after = draw([3, 4, 1])
    #expect(before["1"] == after["1"])
    #expect(before["3"] == after["3"])
    #expect(Set(after.values).count == 3)
  }

}
