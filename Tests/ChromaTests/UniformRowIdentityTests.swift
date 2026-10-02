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

  @Test func equivalentLayoutsReuseIdentity() {
    let controller = ScrollViewController()
    let first = controller.rowIdentity(for: [Item(id: 1)])
    let second = controller.rowIdentity(for: [Item(id: 1)])
    let layout = Interaction.ScrollLayout(width: 100, spacing: 0, rows: .uniform(count: 1, height: 20, keys: first))
    #expect(layout == Interaction.ScrollLayout(width: 100, spacing: 0, rows: .uniform(count: 1, height: 20, keys: second)))
    #expect(layout.index(of: StructuralKey(1)) == 0)
  }
}
