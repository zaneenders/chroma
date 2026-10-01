struct NodeID: Hashable, Sendable {
  let index: Int
  let generation: UInt64
}

@MainActor
struct NodeStore<Value>: ~Copyable {
  private struct Child {
    let key: StructuralKey
    let id: NodeID
  }

  private struct Slot {
    var generation: UInt64 = 0
    var value: Value?
    var children: [Child] = []
  }

  private var slots: [Slot] = []
  private var freeSlots: [Int] = []

  func contains(_ id: NodeID) -> Bool {
    slots.indices.contains(id.index)
      && slots[id.index].generation == id.generation
      && slots[id.index].value != nil
  }

  func value(for id: NodeID) -> Value? {
    contains(id) ? slots[id.index].value : nil
  }

  func children(of id: NodeID) -> [NodeID]? {
    contains(id) ? slots[id.index].children.map(\.id) : nil
  }

  mutating func insert(_ value: Value) -> NodeID {
    let index: Int
    if let reused = freeSlots.popLast() {
      index = reused
      slots[index].value = value
    } else {
      index = slots.count
      slots.append(Slot(value: value))
    }
    return NodeID(index: index, generation: slots[index].generation)
  }

  @discardableResult
  mutating func update(_ id: NodeID, value: Value) -> Bool {
    guard contains(id) else { return false }
    slots[id.index].value = value
    return true
  }

  // Children are owned by their parent; only roots are removed directly.
  @discardableResult
  mutating func removeRoot(_ id: NodeID) -> Bool {
    guard contains(id) else { return false }
    precondition(!slots.contains { $0.children.contains { $0.id == id } })
    removeSubtree(id)
    return true
  }

  @discardableResult
  mutating func reconcileChildren(
    of parent: NodeID, with values: [(key: StructuralKey, value: Value)]
  ) -> [NodeID]? {
    guard contains(parent) else { return nil }
    precondition(Set(values.map(\.key)).count == values.count, "Duplicate sibling keys")
    var previous = Dictionary(uniqueKeysWithValues: slots[parent.index].children.map { ($0.key, $0.id) })
    var children: [Child] = []
    children.reserveCapacity(values.count)
    for (key, value) in values {
      let id: NodeID
      if let existing = previous.removeValue(forKey: key) {
        id = existing
        update(id, value: value)
      } else {
        id = insert(value)
      }
      children.append(Child(key: key, id: id))
    }
    for id in previous.values { removeSubtree(id) }
    slots[parent.index].children = children
    return children.map(\.id)
  }

  private mutating func removeSubtree(_ id: NodeID) {
    for child in slots[id.index].children { removeSubtree(child.id) }
    precondition(slots[id.index].generation < UInt64.max, "Node generation exhausted")
    slots[id.index].children = []
    slots[id.index].value = nil
    slots[id.index].generation += 1
    freeSlots.append(id.index)
  }
}
