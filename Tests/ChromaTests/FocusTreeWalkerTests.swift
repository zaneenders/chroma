import Testing

@testable import Chroma

struct FocusTreeWalkerTests {
  private func leaf(_ id: UInt64, x: Float = 0, y: Float = 0) -> FocusNode {
    FocusNode(kind: .leaf(WidgetID(rawValue: id)), rect: Rect(x: x, y: y, width: 10, height: 10))
  }

  private func group(_ axis: FocusNode.Axis? = nil, _ children: [FocusNode]) -> FocusNode {
    let group = FocusNode(kind: .group, rect: .zero, axis: axis)
    group.children = children
    return group
  }

  private func move(_ command: NavigationCommand, walker: inout FocusTreeWalker) -> Bool {
    walker.move(command)
  }

  @Test func directionalMovementUsesVisiblePositions() {
    let root = group(
      .vertical,
      [
        group(.horizontal, [leaf(1, x: 0, y: 0), leaf(2, x: 20, y: 0)]),
        group(.horizontal, [leaf(3, x: 0, y: 20), leaf(4, x: 20, y: 20)]),
      ])
    var walker = FocusTreeWalker(root: root, path: [0, 1])!

    #expect(move(.down, walker: &walker))
    #expect(walker.path == [1, 1])
    #expect(move(.left, walker: &walker))
    #expect(walker.path == [1, 0])
    #expect(move(.up, walker: &walker))
    #expect(walker.path == [0, 0])
  }

  @Test func nestedLayoutHandlesMovementBeforeAnOuterContainer() {
    let root = group(
      .vertical,
      [
        group(.horizontal, [leaf(1, x: 0, y: 0), leaf(2, x: 20, y: 0)]),
        leaf(3, x: 0, y: 20),
      ])
    var walker = FocusTreeWalker(root: root, path: [0, 0])!

    #expect(move(.right, walker: &walker))
    #expect(walker.path == [0, 1])
  }

  @Test func movementBetweenUnevenGroupsUsesTheNearestLeaf() {
    let root = group(
      .vertical,
      [
        group(.horizontal, [leaf(1, x: 0, y: 0), leaf(2, x: 20, y: 0), leaf(3, x: 40, y: 0)]),
        group(.horizontal, [leaf(4, x: 0, y: 20)]),
      ])
    var walker = FocusTreeWalker(root: root, path: [0, 2])!

    #expect(move(.down, walker: &walker))
    #expect(walker.path == [1, 0])
    #expect(move(.up, walker: &walker))
    #expect(walker.path == [0, 0])
  }

  @Test func oppositeDirectionsReturnToTheSameLeaf() {
    let root = group(
      .vertical,
      [
        group(.horizontal, [leaf(1, x: 0, y: 0), leaf(2, x: 20, y: 0), leaf(3, x: 40, y: 0)]),
        group(.horizontal, [leaf(4, x: 0, y: 20), leaf(5, x: 20, y: 20), leaf(6, x: 40, y: 20)]),
      ])
    var walker = FocusTreeWalker(root: root, path: [0, 1])!

    #expect(move(.down, walker: &walker))
    #expect(walker.path == [1, 1])
    #expect(move(.up, walker: &walker))
    #expect(walker.path == [0, 1])
  }

  @Test func movementSelectsOnlyLeaves() {
    let root = group(.vertical, [group(.horizontal, [leaf(1)])])
    let walker = FocusTreeWalker(root: root, path: [0, 0])!

    #expect(walker.path == [0, 0])
    #expect(FocusTreeWalker(root: root, path: [0]) == nil)
  }

  @Test func boundariesAndInvalidPathsDoNotMove() {
    let root = group(.horizontal, [leaf(1)])
    var walker = FocusTreeWalker(root: root, path: [0])!

    #expect(!move(.left, walker: &walker))
    #expect(walker.path == [0])
    #expect(FocusTreeWalker(root: root, path: [1]) == nil)
  }
}
