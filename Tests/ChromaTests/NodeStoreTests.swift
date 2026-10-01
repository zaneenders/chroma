import Testing

@testable import Chroma

@MainActor
struct NodeStoreTests {
  @Test func reusedSlotsRejectStaleHandles() {
    var store = NodeStore<String>()
    let first = store.insert("first")
    let sibling = store.insert("sibling")
    #expect((store.removeRoot(first)) == true)
    let replacement = store.insert("replacement")
    #expect((replacement.index == first.index) == true)
    #expect((replacement.generation != first.generation) == true)
    #expect((!store.contains(first)) == true)
    #expect((store.value(for: first) == nil) == true)
    #expect((store.children(of: first) == nil) == true)
    #expect((!store.update(first, value: "stale")) == true)
    #expect((!store.removeRoot(first)) == true)
    #expect((store.value(for: replacement) == "replacement") == true)
    #expect((store.value(for: sibling) == "sibling") == true)
    #expect((!store.contains(NodeID(index: -1, generation: 0))) == true)
    #expect((!store.contains(NodeID(index: 100, generation: 0))) == true)
  }

  @Test func keyedRowsKeepHandlesButUpdateValuesWhenReordered() throws {
    var store = NodeStore<String>()
    let parent = store.insert("list")
    let initialRows = store.reconcileChildren(
      of: parent,
      with: [
        (StructuralKey(1), "one"), (StructuralKey(2), "two"),
      ])
    let first = try #require(initialRows)
    let reorderedRows = store.reconcileChildren(
      of: parent,
      with: [
        (StructuralKey(2), "updated two"), (StructuralKey(1), "updated one"),
      ])
    let reordered = try #require(reorderedRows)
    #expect((reordered == first.reversed()) == true)
    #expect((store.children(of: parent) == reordered) == true)
    #expect((store.value(for: first[0]) == "updated one") == true)
    #expect((store.value(for: first[1]) == "updated two") == true)
  }

  @Test func keysAreParentScopedAndTypeSensitive() throws {
    var store = NodeStore<String>()
    let left = store.insert("left")
    let right = store.insert("right")
    let leftChildren = store.reconcileChildren(
      of: left,
      with: [
        (StructuralKey(1), "integer"), (StructuralKey("1"), "string"),
      ])
    let leftRows = try #require(leftChildren)
    let rightChildren = store.reconcileChildren(
      of: right,
      with: [
        (StructuralKey(1), "other integer")
      ])
    let rightRows = try #require(rightChildren)
    #expect((Set(leftRows + rightRows).count == 3) == true)
  }

  @Test func removedRowsInvalidateDescendantsAndReinsertionGetsANewHandle() throws {
    var store = NodeStore<String>()
    let root = store.insert("root")
    let initialRows = store.reconcileChildren(of: root, with: [(StructuralKey(1), "row")])
    let rows = try #require(initialRows)
    let childRows = store.reconcileChildren(
      of: rows[0], with: [(StructuralKey(1), "descendant")])
    let descendants = try #require(childRows)
    #expect((store.reconcileChildren(of: root, with: []) == []) == true)
    #expect((!store.contains(rows[0])) == true)
    #expect((!store.contains(descendants[0])) == true)
    #expect((store.reconcileChildren(of: rows[0], with: []) == nil) == true)
    let replacementRows = store.reconcileChildren(
      of: root, with: [(StructuralKey(1), "new row")])
    let replacement = try #require(replacementRows)
    #expect((replacement[0] != rows[0]) == true)
    #expect((store.removeRoot(root)) == true)
    #expect((!store.contains(replacement[0])) == true)
  }

  @Test func storageGrowthKeepsExistingHandlesValid() {
    var store = NodeStore<Int>()
    let first = store.insert(0)
    for value in 1...1_000 { _ = store.insert(value) }
    #expect((store.value(for: first) == 0) == true)
    #expect((store.update(first, value: 42)) == true)
    #expect((store.value(for: first) == 42) == true)
  }

  @Test func borrowedReadsAndShortMutationsKeepParentsAndGenerationsValid() throws {
    var store = NodeStore<[Int]>()
    let root = store.insert([0])
    let rows = store.reconcileChildren(of: root, with: [(StructuralKey(1), [1, 2])])
    let child = try #require(rows?.first)
    #expect((store.parent(of: root) == nil) == true)
    #expect((store.parent(of: child) == root) == true)
    let sum = store.withValue(for: child) { $0.reduce(0, +) }
    #expect(sum == 3)
    store.modify(child) { $0.append(3) }
    let updated = store.withValue(for: child) { $0.count }
    #expect(updated == 3)
    _ = store.reconcileChildren(of: root, with: [])
    #expect((store.parent(of: child) == nil) == true)
  }

  private final class LifetimeProbe {}

  @Test func removedValuesAreReleased() throws {
    var store = NodeStore<LifetimeProbe>()
    let root = store.insert(LifetimeProbe())
    var value: LifetimeProbe? = LifetimeProbe()
    weak let retained = value
    let mountedRows = store.reconcileChildren(of: root, with: [(StructuralKey(1), value!)])
    _ = try #require(mountedRows)
    value = nil
    #expect((retained != nil) == true)
    _ = store.reconcileChildren(of: root, with: [])
    #expect((retained == nil) == true)
  }
}
