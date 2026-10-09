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

  @Test func identifiableInitializerUsesKeysWithoutAnExplicitRevision() {
    let controller = ScrollViewController()
    _ = ScrollView(data: [Item(id: 7), Item(id: 9)], rowHeight: 20, controller: controller) { _ in
      Text("row")
    }
    #expect(controller.uniformRowIdentity?.keys == [StructuralKey(7), StructuralKey(9)])
    #expect(controller.uniformRowIdentity?.indices[StructuralKey(9)] == 1)
  }

  @Test func unconstrainedInitializerRemainsPositionalWithOrWithoutARevision() {
    let controller = ScrollViewController()
    func positional<Data: RandomAccessCollection>(_ data: Data, revision: UInt64?) -> ScrollView {
      ScrollView(data: data, rowHeight: 20, controller: controller, identityRevision: revision) { _ in
        Text("row")
      }
    }
    _ = positional([Item(id: 7), Item(id: 9)], revision: nil)
    #expect(controller.uniformRowIdentity == nil)
    _ = positional([Item(id: 7), Item(id: 9)], revision: 1)
    #expect(controller.uniformRowIdentity == nil)
  }

  private struct CountedItem: Identifiable {
    let key: Int
    let reads: IDReads
    var id: Int {
      reads.count += 1
      return key
    }
  }

  @Test func unchangedRevisionDoesNotVisitAnyIDs() {
    let controller = ScrollViewController()
    let reads = IDReads()
    let items = (0..<100_000).map { CountedItem(key: $0, reads: reads) }
    let first = controller.rowIdentity(for: items, identityRevision: 1)
    #expect(reads.count == items.count)
    reads.count = 0
    for _ in 0..<10 {
      #expect(controller.rowIdentity(for: items, identityRevision: 1) === first)
    }
    #expect(reads.count == 0)
  }

  @Test func newRevisionUpdatesReorderedAndReplacedIDs() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: 1), Item(id: 2)], identityRevision: 1)
    let reordered = controller.rowIdentity(for: [Item(id: 2), Item(id: 1)], identityRevision: 2)
    #expect(reordered !== first)
    #expect(reordered.indices[StructuralKey(1)] == 1)
    let replaced = controller.rowIdentity(for: [Item(id: 2), Item(id: 3)], identityRevision: 3)
    #expect(replaced !== reordered)
    #expect(replaced.indices[StructuralKey(1)] == nil)
    #expect(replaced.indices[StructuralKey(3)] == 1)
    #expect(first.indices[StructuralKey(1)] == 0)
  }

  @Test func revisionFastPathStillChecksCountAndIDType() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: 1)], identityRevision: 1)
    let larger = controller.rowIdentity(for: [Item(id: 1), Item(id: 2)], identityRevision: 1)
    #expect(larger !== first)
    #expect(larger.keys.count == 2)
    let changedType = controller.rowIdentity(for: [Item(id: Int64(1)), Item(id: Int64(2))], identityRevision: 1)
    #expect(changedType !== larger)
    #expect(changedType.indices[StructuralKey(Int64(2))] == 1)
  }

  @Test func unrevisionedAccessCannotLeaveAStaleRevisionToken() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: 1)], identityRevision: 1)
    #expect(controller.rowIdentity(for: [Item(id: 1)]) === first)
    let replacement = controller.rowIdentity(for: [Item(id: 2)], identityRevision: 1)
    #expect(replacement !== first)
    #expect(replacement.indices[StructuralKey(2)] == 0)
    _ = controller.rowIdentity(for: [Item(id: 3)])
    let restored = controller.rowIdentity(for: [Item(id: 2)], identityRevision: 1)
    #expect(restored.indices[StructuralKey(2)] == 0)
  }

  @Test func unchangedIdentityRevisionStillRefreshesRowValuesAndCallbacks() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let controller = ScrollViewController()
    var value = 1
    var label = "old"
    var actions: [String] = []
    runtime.content = DeferredBlock {
      let capturedLabel = label
      return ScrollView(
        data: [Item(id: 1, value: value)], rowHeight: 40,
        controller: controller, identityRevision: 1
      ) { item in
        Button(capturedLabel) { actions.append("\(item.value):\(capturedLabel)") }
      }
    }
    _ = runtime.render(viewport: Size(width: 200, height: 100), input: InputState(), onChange: {})
    runtime.interaction.focusFirstControlForTest()
    let identity = controller.uniformRowIdentity
    value = 10
    label = "new"
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    #expect(actions == ["10:new"])
    #expect(controller.uniformRowIdentity === identity)
  }
}
