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
}
