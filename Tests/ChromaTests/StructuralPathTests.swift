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
    var replaced = nested
    replaced.children = [
      Probe(name: "third", recorder: recorder),
      Probe(name: "fourth", recorder: recorder),
    ]
    let second = render(replaced, recorder: recorder)
    #expect(second["third"] != second["fourth"])
    #expect(first == render(nested, recorder: recorder))
  }

  private struct Pair: PrimitiveBlock {
    let recorder: Recorder

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

}
