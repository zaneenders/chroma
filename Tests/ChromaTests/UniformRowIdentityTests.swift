import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct UniformRowIdentityTests {
  private struct Item<ID: Hashable & Sendable>: Identifiable {
    let id: ID
    var value = 0
  }

  @Test func unchangedIDsReuseIdentityWhenContentChanges() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: 1), Item(id: 2)])
    let second = controller.rowIdentity(for: [Item(id: 1, value: 10), Item(id: 2, value: 20)])
    #expect(first === second)
  }

  @Test func structuralChangesReplaceIdentityAndUpdateLookup() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: 1), Item(id: 2)])
    let reordered = controller.rowIdentity(for: [Item(id: 2), Item(id: 1)])
    #expect(first !== reordered)
    #expect(reordered.indices[StructuralKey(1)] == 1)
    #expect(first.indices[StructuralKey(1)] == 0)
    let replaced = controller.rowIdentity(for: [Item(id: 2), Item(id: 3)])
    #expect(reordered !== replaced)
    #expect(replaced.indices[StructuralKey(1)] == nil)
    #expect(replaced.indices[StructuralKey(3)] == 1)
    let removed = controller.rowIdentity(for: [Item(id: 3)])
    #expect(replaced !== removed)
    #expect(removed.indices[StructuralKey(3)] == 0)
  }

  @Test func differentIDTypesDoNotReuseIdentity() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: Int(1))])
    let second = controller.rowIdentity(for: [Item(id: Int64(1))])
    #expect(first !== second)
    #expect(second.indices[StructuralKey(Int(1))] == nil)
    #expect(second.indices[StructuralKey(Int64(1))] == 0)
  }

  @Test func emptyAndGrowingCollectionsReplaceOnlyChangedSnapshots() {
    let controller = ScrollViewController()
    let empty = controller.rowIdentity(for: [Item<Int>]())
    #expect(controller.rowIdentity(for: [Item<Int>]()) === empty)
    let first = controller.rowIdentity(for: [Item(id: 1)])
    #expect(first !== empty)
    let appended = controller.rowIdentity(for: [Item(id: 1), Item(id: 2)])
    #expect(appended !== first)
    #expect(appended.indices[StructuralKey(2)] == 1)
    #expect(first.matches([Item(id: 1)]))
    let cleared = controller.rowIdentity(for: [Item<Int>]())
    #expect(cleared !== appended)
    #expect(cleared.keys.isEmpty)
    #expect(cleared.indices.isEmpty)
  }

  @Test func slicedCollectionsUseTheirOwnStartIndex() {
    let controller = ScrollViewController()
    let items = (0..<6).map { Item(id: $0) }
    let first = controller.rowIdentity(for: items[2..<5])
    #expect(controller.rowIdentity(for: Array(items[2..<5])) === first)
    #expect(controller.rowIdentity(for: items[2..<5]) === first)
    #expect(first.indices[StructuralKey(2)] == 0)
    #expect(first.indices[StructuralKey(4)] == 2)
    let shifted = controller.rowIdentity(for: items[3..<6])
    #expect(shifted !== first)
    #expect(shifted.indices[StructuralKey(3)] == 0)
  }

  private struct NoncontiguousItems: RandomAccessCollection {
    let items: ArraySlice<Item<Int>>
    var startIndex: Int { items.startIndex }
    var endIndex: Int { items.endIndex }
    subscript(index: Int) -> Item<Int> { items[index] }
    func index(after index: Int) -> Int { index + 1 }
    func index(before index: Int) -> Int { index - 1 }
  }

  @Test func noncontiguousCollectionsReuseIdentityAndDetectChanges() {
    let controller = ScrollViewController()
    let items = (0..<6).map { Item(id: $0) }
    let data = NoncontiguousItems(items: items[2..<5])
    #expect(data.withContiguousStorageIfAvailable { _ in true } == nil)
    let first = controller.rowIdentity(for: data)
    #expect(controller.rowIdentity(for: data) === first)
    #expect(controller.rowIdentity(for: items[2..<5]) === first)
    #expect(controller.rowIdentity(for: NoncontiguousItems(items: items[3..<6])) !== first)
    #expect(first.matches(data))
  }

  @Test(arguments: [0, 1, 2])
  func comparisonDetectsChangesAtEveryPosition(position: Int) {
    let controller = ScrollViewController()
    let items = [Item(id: 1), Item(id: 2), Item(id: 3)]
    let first = controller.rowIdentity(for: items)
    var changed = items
    changed[position] = Item(id: 4)
    #expect(!first.matches(changed))
    #expect(!first.matches(NoncontiguousItems(items: changed[...])))
    let replacement = controller.rowIdentity(for: changed)
    #expect(replacement !== first)
    #expect(replacement.indices[StructuralKey(4)] == position)
    #expect(first.matches(items))
  }

  private final class ReferenceID: Hashable, Sendable {
    let value: Int
    init(_ value: Int) { self.value = value }
    static func == (lhs: ReferenceID, rhs: ReferenceID) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) { hasher.combine(value) }
  }

  @Test func referenceIDsRemainAliveUntilTheirLastSnapshotIsReleased() {
    let controller = ScrollViewController()
    weak var oldID: ReferenceID?
    var retained: TypedUniformRowIdentity<ReferenceID>?
    do {
      let id = ReferenceID(1)
      oldID = id
      retained = controller.rowIdentity(for: [Item(id: id)])
    }
    _ = controller.rowIdentity(for: [Item(id: ReferenceID(2))])
    #expect(oldID != nil)
    #expect(retained?.matches([Item(id: ReferenceID(1))]) == true)
    retained = nil
    #expect(oldID == nil)
  }

  @Test func equivalentLayoutsReuseIdentity() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: 1)])
    let second = controller.rowIdentity(for: [Item(id: 1)])
    let layout = Interaction.ScrollLayout(width: 100, spacing: 0, rows: .uniform(count: 1, height: 20, keys: first))
    #expect(
      layout == Interaction.ScrollLayout(width: 100, spacing: 0, rows: .uniform(count: 1, height: 20, keys: second)))
    #expect(layout.index(of: StructuralKey(1)) == 0)
  }

  private final class IDReads {
    var count = 0
  }

  private struct CountedItem: Identifiable {
    let value: Int
    let reads: IDReads
    var id: Int {
      reads.count += 1
      return value
    }
  }

  @Test func explicitRevisionSkipsEveryIDReadOnReuse() {
    let controller = ScrollViewController()
    let reads = IDReads()
    let items = (0..<10_000).map { CountedItem(value: $0, reads: reads) }
    let revision = ScrollView.IdentityRevision(source: "items", revision: 0)
    let first = controller.rowIdentity(for: items, revision: revision)
    #expect(reads.count == items.count)
    reads.count = 0
    for _ in 0..<5 {
      #expect(controller.rowIdentity(for: items, revision: revision) === first)
    }
    #expect(reads.count == 0)
    #expect(controller.rowIdentity(for: items) === first)
    #expect(reads.count == items.count)
    // Omitting the contract clears it; restoring one must revalidate its IDs.
    reads.count = 0
    #expect(controller.rowIdentity(for: items, revision: revision) !== first)
    #expect(reads.count == items.count)
  }

  @Test func unchangedRevisionAvoidsIDReadsAcrossInputAndPresentation() {
    let controller = ScrollViewController()
    let reads = IDReads()
    let items = (0..<10_000).map { CountedItem(value: $0, reads: reads) }
    let host = HeadlessHost(size: Size(width: 200, height: 100))
    defer { host.close() }
    host.content = DeferredBlock {
      ScrollView(
        data: items, rowHeight: 20, controller: controller,
        identityRevision: .init(source: "items", revision: 0)
      ) { _ in Color.white }
    }
    _ = host.render()
    #expect(reads.count == items.count)
    reads.count = 0
    for _ in 0..<5 {
      host.sendInput(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -20)))
    }
    #expect(host.renderIfNeeded() != nil)
    #expect(reads.count == 0)
  }

  @Test func revisionsRebuildForAllStructuralMutations() {
    let controller = ScrollViewController()
    let sequences = [[1, 2], [2, 1], [2, 3], [2, 3, 4], [3, 4], [], [5]]
    var previous: TypedUniformRowIdentity<Int>?
    for (revision, ids) in sequences.enumerated() {
      let identity = controller.rowIdentity(
        for: ids.map { Item(id: $0) },
        revision: .init(source: "items", revision: revision))
      #expect(identity !== previous)
      #expect(identity.matches(ids.map { Item(id: $0) }))
      for (index, id) in ids.enumerated() { #expect(identity.indices[StructuralKey(id)] == index) }
      previous = identity
    }
  }

  @Test func explicitContractSeparatesSourcesAndTypes() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: 1)], revision: .init(source: "first", revision: 0))
    let replaced = controller.rowIdentity(for: [Item(id: 2)], revision: .init(source: "second", revision: 0))
    #expect(replaced !== first)
    #expect(replaced.indices[StructuralKey(2)] == 0)
    let typeChanged = controller.rowIdentity(for: [Item(id: Int64(2))], revision: .init(source: "second", revision: 0))
    #expect(typeChanged !== replaced)
    #expect(typeChanged.indices[StructuralKey(Int64(2))] == 0)
    #expect(ScrollView.IdentityRevision(source: Int(1), revision: 0) != .init(source: Int64(1), revision: 0))
    #expect(
      ScrollView.IdentityRevision(source: "first", revision: Int(1)) != .init(source: "first", revision: Int64(1)))
  }

  @Test func explicitContractHandlesSlicesNoncontiguousDataAndCountChanges() {
    let controller = ScrollViewController()
    let items = (0..<6).map { Item(id: $0) }
    let revision = ScrollView.IdentityRevision(source: "slice", revision: 0)
    let first = controller.rowIdentity(for: items[2..<5], revision: revision)
    #expect(controller.rowIdentity(for: NoncontiguousItems(items: items[2..<5]), revision: revision) === first)
    #expect(first.indices[StructuralKey(2)] == 0)
    let shifted = controller.rowIdentity(
      for: NoncontiguousItems(items: items[3..<6]), revision: .init(source: "slice", revision: 1))
    #expect(shifted !== first)
    #expect(shifted.indices[StructuralKey(3)] == 0)
    // Even an incorrectly unchanged contract cannot retain an incompatible count.
    let smaller = controller.rowIdentity(for: items[3..<5], revision: .init(source: "slice", revision: 1))
    #expect(smaller !== shifted)
    #expect(smaller.keys.count == 2)
  }

  @Test func conservativeCallCannotLeaveAnExplicitContractActive() {
    let controller = ScrollViewController()
    let revision = ScrollView.IdentityRevision(source: "items", revision: 0)
    _ = controller.rowIdentity(for: [Item(id: 1)], revision: revision)
    let fallback = controller.rowIdentity(for: [Item(id: 2)])
    let explicit = controller.rowIdentity(for: [Item(id: 1)], revision: revision)
    #expect(explicit !== fallback)
    #expect(explicit.indices[StructuralKey(1)] == 0)
  }

}
