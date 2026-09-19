import Testing

@testable import Chroma

struct FocusTreeWalkerTests {
  private func leaf(_ id: UInt64) -> FocusNode {
    FocusNode(kind: .leaf(WidgetID(rawValue: id)), rect: .zero)
  }

  private func group(_ axis: FocusNode.Axis? = nil, _ children: [FocusNode]) -> FocusNode {
    let group = FocusNode(kind: .group, rect: .zero, axis: axis)
    group.children = children
    return group
  }

  private func move(_ command: NavigationCommand, walker: inout FocusTreeWalker) -> Bool {
    walker.move(command)
  }

  @Test func directionalMovementPreservesDescendantPath() {
    let root = group(
      .vertical,
      [
        group(.horizontal, [leaf(1), leaf(2)]),
        group(.horizontal, [leaf(3), leaf(4)]),
      ])
    var walker = FocusTreeWalker(root: root, path: [0, 1])!

    do {
      let didMove = move(.down, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [1, 1])
    do {
      let didMove = move(.left, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [1, 0])
    do {
      let didMove = move(.up, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [0, 0])
  }

  @Test func unevenDestinationUsesTheFacingEdge() {
    let root = group(
      .vertical,
      [
        group(.horizontal, [leaf(1), leaf(2), leaf(3)]),
        group(.horizontal, [leaf(4)]),
      ])
    var walker = FocusTreeWalker(root: root, path: [0, 2])!

    do {
      let didMove = move(.down, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [1, 0])
    do {
      let didMove = move(.up, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [0, 0])
  }

  @Test func directionalMovementContinuesPastAnExhaustedInnerGroup() {
    let root = group(
      .vertical,
      [
        group(.vertical, [group(.horizontal, [leaf(1), leaf(2)])]),
        group(.horizontal, [leaf(3), leaf(4)]),
      ])
    var walker = FocusTreeWalker(root: root, path: [0, 0, 1])!

    do {
      let didMove = move(.down, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [1, 0])

    do {
      let didMove = move(.up, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [0, 0])
  }

  @Test func inwardAndOutwardSelectOneStructuralLevel() {
    let root = group(.vertical, [group(.horizontal, [leaf(1)])])
    var walker = FocusTreeWalker(root: root, path: [0, 0])!

    do {
      let didMove = move(.outward, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [0])
    do {
      let didMove = move(.outward, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [])
    do {
      let didMove = move(.inward, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [0])
    do {
      let didMove = move(.inward, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [0, 0])
    do {
      let didMove = move(.inward, walker: &walker)
      #expect(!didMove)
    }
    do {
      let didMove = move(.outward, walker: &walker)
      #expect(didMove)
    }
    #expect(walker.path == [0])
  }

  @Test func boundariesAndInvalidPathsDoNotMove() {
    let root = group(.horizontal, [leaf(1)])
    var walker = FocusTreeWalker(root: root, path: [0])!

    do {
      let didMove = move(.left, walker: &walker)
      #expect(!didMove)
    }
    #expect(walker.path == [0])
    #expect(FocusTreeWalker(root: root, path: [1]) == nil)
  }
}
