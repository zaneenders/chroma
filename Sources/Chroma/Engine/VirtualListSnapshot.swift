@MainActor
public final class VirtualListSnapshot<ID: Hashable> {
  public let revision: UInt64
  public let ids: [ID]
  private let indices: [ID: Int]

  // Reuse a snapshot until membership or order changes; row content can change independently.
  public init(ids: some Sequence<ID>, revision: UInt64 = 0) {
    self.revision = revision
    self.ids = Array(ids)
    var indices: [ID: Int] = [:]
    indices.reserveCapacity(self.ids.count)
    for (index, id) in self.ids.enumerated() {
      precondition(indices.updateValue(index, forKey: id) == nil, "Duplicate virtual list IDs")
    }
    self.indices = indices
  }

  public var count: Int { ids.count }

  public func index(of id: ID) -> Int? { indices[id] }
}
