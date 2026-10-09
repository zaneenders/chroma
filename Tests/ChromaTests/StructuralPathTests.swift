import Testing

@testable import Chroma

@MainActor
struct StructuralPathTests {
  private final class Recorder {
    var measured: [String: StructuralPath] = [:]
    var drawn: [String: StructuralPath] = [:]
  }

  private enum ComponentIdentity {}
  private enum CollectionIdentity {}

  private func probe(
    _ name: String, recorder: Recorder, into buffer: inout LayoutBuffer, context: LayoutContext
  ) -> LayoutNode {
    buffer.customLeaf(
      context: context,
      measure: { _ in
        recorder.measured[name] = context.structuralPath
        return Size(width: 10, height: 10)
      }, register: { _ in }, paint: { _, _ in recorder.drawn[name] = context.structuralPath })
  }

  private func render(_ build: LayoutBuilder, recorder: Recorder) -> [String: StructuralPath] {
    let context = LayoutContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    recorder.measured = [:]
    recorder.drawn = [:]
    _ = measureLayout(build, proposal: rect.size, context: context)
    beginTestFrame(context.interaction, input: InputState())
    var list = DrawList()
    var buffer = LayoutBuffer()
    let root = build(&buffer, context)
    buffer.register(root, in: rect)
    buffer.paint(root, into: &list, in: rect)
    context.interaction.endFrame()
    #expect(recorder.measured == recorder.drawn)
    return recorder.drawn
  }

  @Test func explicitKeysAreParentScopedTypeSensitiveAndPreserveCollectionLayout() {
    let recorder = Recorder()
    func content(_ key: some Hashable & Sendable) -> LayoutBuilder {
      { buffer, context in
        let collectionContext = context.childScope(0).keyed(key)
        var children = [1, 2].map { value in
          let rowContext = collectionContext.keyed(value)
          let child = probe("row\(value)", recorder: recorder, into: &buffer, context: rowContext)
          return buffer.padding(child, 0, context: rowContext)
        }
        children.append(probe("sibling", recorder: recorder, into: &buffer, context: context.childScope(1).keyed(key)))
        return buffer.stack(children, axis: .vertical, context: context)
      }
    }
    let first = render(content(1), recorder: recorder)
    #expect(first == render(content(1), recorder: recorder))
    let changed = render(content("1"), recorder: recorder)
    #expect(first["row1"] != changed["row1"])
    #expect(first["row1"] != first["row2"])
    #expect(first["row1"] != first["sibling"])
    #expect(measureLayout(content(1), proposal: Size(width: 100, height: 100), context: LayoutContext()).height == 30)
  }

  @Test func conditionalKeysPreserveSiblingSlots() {
    let recorder = Recorder()
    func content(_ flag: Bool) -> LayoutBuilder {
      { buffer, context in
        var children: [LayoutNode] = []
        if flag {
          children.append(probe("optional", recorder: recorder, into: &buffer, context: context.childScope(0)))
        }
        let branchContext = context.childScope(1).keyed(flag ? "then" : "else")
        children.append(probe("branch", recorder: recorder, into: &buffer, context: branchContext))
        children.append(probe("sibling", recorder: recorder, into: &buffer, context: context.childScope(2)))
        return buffer.stack(children, axis: .vertical, context: context)
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
    func content(reversed: Bool) -> LayoutBuilder {
      { buffer, context in
        let children = ["first", "second"].enumerated().map { index, name in
          probe(
            name, recorder: recorder, into: &buffer,
            context: context.childScope(index).component(ComponentIdentity.self))
        }
        return buffer.stack(children, axis: .horizontal, reversed: reversed, context: context)
      }
    }
    let first = render(content(reversed: false), recorder: recorder)
    #expect(first["first"] != first["second"])
    #expect(first == render(content(reversed: true), recorder: recorder))
  }

  @Test func nestedChildArraysPreserveExplicitIdentities() {
    let recorder = Recorder()
    let nested: LayoutBuilder = { buffer, context in
      let first = probe("first", recorder: recorder, into: &buffer, context: context.childScope(0))
      let second = probe("second", recorder: recorder, into: &buffer, context: context.childScope(1).childScope(0))
      let inner = buffer.overlay([second], group: false, context: context.childScope(1))
      return buffer.overlay([first, inner], group: false, context: context)
    }
    let first = render(nested, recorder: recorder)
    #expect(first["first"] != first["second"])
    let replaced: LayoutBuilder = { buffer, context in
      let children = ["third", "fourth"].enumerated().map { index, name in
        probe(name, recorder: recorder, into: &buffer, context: context.childScope(index))
      }
      return buffer.overlay(children, group: false, context: context)
    }
    let second = render(replaced, recorder: recorder)
    #expect(second["third"] != second["fourth"])
    #expect(first == render(nested, recorder: recorder))
  }

  @Test func emittedContainerKeepsItsOriginalChildren() {
    let recorder = Recorder()
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    let first = probe("first", recorder: recorder, into: &buffer, context: context.childScope(0))
    let second = probe("second", recorder: recorder, into: &buffer, context: context.childScope(1))
    var children = [first, second]
    let root = buffer.stack(children, axis: .vertical, context: context)
    children.removeAll()
    #expect(children.isEmpty)
    #expect(buffer.sizeThatFits(root, Size(width: 100, height: 100)) == Size(width: 10, height: 20))
    beginTestFrame(context.interaction, input: InputState())
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    buffer.register(root, in: rect)
    var list = DrawList()
    buffer.paint(root, into: &list, in: rect)
    context.interaction.endFrame()
    #expect(Set(recorder.drawn.keys) == ["first", "second"])
  }

  @Test func customContainerSlotsDoNotDependOnTraversalOrder() {
    let recorder = Recorder()
    let pair: LayoutBuilder = { buffer, context in
      let first = probe("first", recorder: recorder, into: &buffer, context: context.childScope(0))
      let second = probe("second", recorder: recorder, into: &buffer, context: context.childScope(1))
      return buffer.overlay([second, first], group: false, context: context)
    }
    let paths = render(pair, recorder: recorder)
    #expect(paths["first"] != paths["second"])
    #expect(paths == render(pair, recorder: recorder))
  }

  @Test func stylingOperationsAreIdentityTransparent() {
    let recorder = Recorder()
    let plain: LayoutBuilder = { buffer, context in
      probe("content", recorder: recorder, into: &buffer, context: context)
    }
    let expected = render(plain, recorder: recorder)
    let styled: LayoutBuilder = { buffer, context in
      buffer.background(
        context: context,
        content: { buffer, context in
          let child = plain(&buffer, context)
          let padded = buffer.padding(child, 4, context: context)
          let sized = buffer.sizing(padded, x: .grow, context: context)
          let border = buffer.border(sized, color: .white, context: context)
          let rounded = buffer.roundedBackground(border, color: .white, radii: CornerRadii(2), context: context)
          return buffer.clip(rounded, context: context)
        }, background: { buffer, context in buffer.color(.white, context: context) })
    }
    #expect(render(styled, recorder: recorder) == expected)
    #expect(
      render(
        { buffer, context in
          buffer.background(
            context: context,
            content: { buffer, context in
              let child = styled(&buffer, context)
              return buffer.padding(child, 12, context: context)
            }, background: { buffer, context in buffer.color(.white, context: context) })
        }, recorder: recorder) == expected)
    let component: LayoutBuilder = { buffer, context in plain(&buffer, context.component(ComponentIdentity.self)) }
    #expect(render(component, recorder: recorder) != expected)
    let componentPath = render(component, recorder: recorder)
    #expect(
      render(
        { buffer, context in
          let child = component(&buffer, context)
          return buffer.padding(child, 4, context: context)
        }, recorder: recorder) == componentPath)
  }

  @Test func backgroundLayersHaveDistinctScopes() {
    let recorder = Recorder()
    let plain: LayoutBuilder = { buffer, context in
      probe("content", recorder: recorder, into: &buffer, context: context)
    }
    let expected = render(plain, recorder: recorder)["content"]
    let layered: LayoutBuilder = { buffer, context in
      buffer.background(
        context: context,
        content: { buffer, context in
          buffer.background(
            context: context, content: plain,
            background: { buffer, context in
              probe("inner", recorder: recorder, into: &buffer, context: context)
            })
        }, background: { buffer, context in probe("outer", recorder: recorder, into: &buffer, context: context) })
    }
    let context = LayoutContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    func draw() -> [String: StructuralPath] {
      recorder.drawn = [:]
      beginTestFrame(context.interaction, input: InputState())
      var list = DrawList()
      var buffer = LayoutBuffer()
      let root = layered(&buffer, context)
      buffer.register(root, in: rect)
      buffer.paint(root, into: &list, in: rect)
      context.interaction.endFrame()
      return recorder.drawn
    }
    let paths = draw()
    #expect(paths["content"] == expected)
    #expect(Set(paths.values).count == 3)
    #expect(draw() == paths)
    recorder.measured = [:]
    _ = measureLayout(layered, proposal: rect.size, context: context)
    #expect(recorder.measured["content"] == expected)
  }

  @Test func transparentOverlayPreservesKeyedChildIdentity() {
    let recorder = Recorder()
    func content(_ ids: [Int]) -> LayoutBuilder {
      { buffer, context in
        let children = ids.map { probe(String($0), recorder: recorder, into: &buffer, context: context.keyed($0)) }
        let overlay = buffer.overlay(children, group: false, context: context)
        return buffer.stack([overlay], axis: .vertical, context: context)
      }
    }
    let distributed: LayoutBuilder = { buffer, context in
      let children = [1, 2].map { value in
        let childContext = context.keyed(value)
        let child = probe(String(value), recorder: recorder, into: &buffer, context: childContext)
        return buffer.padding(child, 0, context: childContext)
      }
      return buffer.stack(children, axis: .vertical, context: context)
    }
    #expect(measureLayout(distributed, proposal: Size(width: 100, height: 100), context: LayoutContext()).height == 20)
    let paths = render(content([1, 2]), recorder: recorder)
    #expect(paths["1"] != paths["2"])
    #expect(render(content([2, 1]), recorder: recorder) == paths)
    let plain: LayoutBuilder = { buffer, context in probe("single", recorder: recorder, into: &buffer, context: context)
    }
    #expect(
      render(
        { buffer, context in
          let child = plain(&buffer, context)
          return buffer.overlay([child], group: false, context: context)
        }, recorder: recorder) == render(plain, recorder: recorder))
  }

  @Test func explicitComponentScopeChangesCollectionIdentity() {
    let recorder = Recorder()
    func content(_ ids: [Int], scoped: Bool) -> LayoutBuilder {
      { buffer, context in
        let childContext = scoped ? context.component(CollectionIdentity.self) : context
        let children = ids.map { probe(String($0), recorder: recorder, into: &buffer, context: childContext.keyed($0)) }
        return buffer.stack(children, axis: .vertical, context: context)
      }
    }
    let stack = content([1, 2], scoped: true)
    #expect(measureLayout(stack, proposal: Size(width: 100, height: 100), context: LayoutContext()).height == 20)
    let paths = render(stack, recorder: recorder)
    #expect(paths["1"] != paths["2"])
    #expect(render(content([2, 1], scoped: true), recorder: recorder) == paths)
    let plain = render(content([1, 2], scoped: false), recorder: recorder)
    for name in ["1", "2"] {
      #expect(paths[name] != plain[name])
      #expect(paths[name]?.segments.contains(.component(ObjectIdentifier(CollectionIdentity.self))) == true)
    }
  }

  private struct Item: Identifiable { let id: Int }

  @Test func keyedCollectionsPreserveItemsAndSiblingSlots() {
    let recorder = Recorder()
    func content(_ ids: [Int]) -> LayoutBuilder {
      { buffer, context in
        var children = ids.map {
          probe(String($0), recorder: recorder, into: &buffer, context: context.childScope(0).keyed($0))
        }
        children.append(probe("sibling", recorder: recorder, into: &buffer, context: context.childScope(1)))
        return buffer.stack(children, axis: .vertical, spacing: 3, context: context)
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
      measureLayout(content([1, 2]), proposal: Size(width: 100, height: 100), context: LayoutContext())
        == Size(width: 10, height: 36))
  }

  @Test(arguments: ["vertical", "horizontal", "overlay"])
  func modifiedCollectionsPreserveLayoutAndPaths(axis: String) {
    let recorder = Recorder()
    func content(_ modified: Bool, ids: [Int]) -> LayoutBuilder {
      { buffer, context in
        var children: [LayoutNode] = []
        for id in ids {
          for (slot, name) in [String(id), "extra-\(id)"].enumerated() {
            let childContext = context.childScope(0).keyed(id).childScope(slot)
            let child: LayoutNode
            if modified {
              child = buffer.background(
                context: childContext,
                content: { buffer, context in
                  let node = probe(name, recorder: recorder, into: &buffer, context: context)
                  let padded = buffer.padding(node, 0, context: context)
                  let bordered = buffer.border(padded, color: .white, context: context)
                  return buffer.clip(bordered, context: context)
                }, background: { buffer, context in buffer.color(.white, context: context) })
            } else {
              child = probe(name, recorder: recorder, into: &buffer, context: childContext)
            }
            children.append(child)
          }
        }
        children.append(probe("sibling", recorder: recorder, into: &buffer, context: context.childScope(1)))
        if axis == "overlay" { return buffer.overlay(children, context: context) }
        return buffer.stack(children, axis: axis == "vertical" ? .vertical : .horizontal, spacing: 3, context: context)
      }
    }
    let proposal = Size(width: 100, height: 100)
    let plain = content(false, ids: [1, 2])
    let styled = content(true, ids: [1, 2])
    let paths = render(plain, recorder: recorder)
    #expect(render(styled, recorder: recorder) == paths)
    #expect(
      measureLayout(plain, proposal: proposal, context: LayoutContext())
        == measureLayout(styled, proposal: proposal, context: LayoutContext()))
    let reordered = render(content(true, ids: [2, 3, 1]), recorder: recorder)
    for (name, path) in paths { #expect(reordered[name] == path) }
    #expect(render(content(true, ids: []), recorder: recorder)["sibling"] == paths["sibling"])
  }

  @Test func collectionPaddingAppliesToEachChild() {
    let recorder = Recorder()
    let build: LayoutBuilder = { buffer, context in
      let children = [1, 2].map { id in
        let childContext = context.keyed(id)
        let child = probe(String(id), recorder: recorder, into: &buffer, context: childContext)
        return buffer.padding(child, 2, context: childContext)
      }
      return buffer.stack(children, axis: .vertical, spacing: 3, context: context)
    }
    #expect(
      measureLayout(build, proposal: Size(width: 100, height: 100), context: LayoutContext())
        == Size(width: 14, height: 31))
  }

  @Test func collectionKeysAreParentScopedAndTypeSensitive() {
    let recorder = Recorder()
    let paths = render(
      { buffer, context in
        let first = probe("first", recorder: recorder, into: &buffer, context: context.childScope(0).keyed(1))
        let second = probe("second", recorder: recorder, into: &buffer, context: context.childScope(1).keyed(1))
        return buffer.stack([first, second], axis: .horizontal, context: context)
      }, recorder: recorder)
    #expect(paths["first"] != paths["second"])
    #expect(StructuralKey(1) != StructuralKey(Int64(1)))
    #expect(StructuralKey(1) == StructuralKey(1))
  }

  @Test(arguments: [false, true])
  func lazyRowsFollowKeysAcrossReordering(uniform: Bool) {
    let recorder = Recorder()
    let controller = ScrollViewController()
    let context = LayoutContext()
    func draw(_ ids: [Int]) -> [String: StructuralPath] {
      recorder.measured = [:]
      recorder.drawn = [:]
      let scroll: ScrollView
      if uniform {
        scroll = ScrollView(data: ids.map { Item(id: $0) }, rowHeight: 10, controller: controller) {
          buffer, context, item in
          probe(String(item.id), recorder: recorder, into: &buffer, context: context)
        }
      } else {
        scroll = ScrollView(
          controller: controller,
          rows: ids.map { id in
            .init(id: WidgetID(String(id))) { buffer, context in
              probe(String(id), recorder: recorder, into: &buffer, context: context)
            }
          })
      }
      beginTestFrame(context.interaction, input: InputState())
      var list = DrawList()
      var buffer = LayoutBuffer()
      let root = buffer.scrollView(scroll, context: context.keyed(WidgetID("list")))
      let rect = Rect(x: 0, y: 0, width: 100, height: 100)
      buffer.register(root, in: rect)
      buffer.paint(root, into: &list, in: rect)
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
