import Observation

enum ScrollRequest: Equatable, Sendable {
  case top
  case bottom
  case offset(Float)
  case visible(Rect)
  case row(StructuralKey)
}

@Observable
@MainActor
public final class ScrollViewController {
  @ObservationIgnored public internal(set) var offset: Float = 0
  @ObservationIgnored public internal(set) var horizontalOffset: Float = 0
  @ObservationIgnored private var identity: WidgetID?

  func restore(id: WidgetID, interaction: Interaction) {
    if let identity, identity != id {
      offset = 0
      horizontalOffset = 0
    }
    identity = id
    if interaction.scrollStates[id] == nil {
      interaction.scrollStates[id] = Interaction.ScrollState(offset: Point(x: horizontalOffset, y: offset))
    }
  }

  var request: ScrollRequest?
  @ObservationIgnored var lazyStackCache = LazyStackCache()
  @ObservationIgnored var uniformRowIdentity: UniformRowIdentity?

  func rowIdentity<Data: RandomAccessCollection>(for data: Data) -> UniformRowIdentity
  where Data.Element: Identifiable, Data.Element.ID: Sendable {
    let ids = data.map(\.id)
    if let cached = uniformRowIdentity, let previous = cached.ids as? [Data.Element.ID], previous == ids {
      return cached
    }
    let identity = UniformRowIdentity(ids: ids)
    uniformRowIdentity = identity
    return identity
  }

  public init() {}
  func scrollToRowKey(_ key: StructuralKey) { request = .row(key) }
  public func scrollToRow(_ id: some Hashable & Sendable) { request = .row(StructuralKey(id)) }

  public func scrollToTop() { request = .top }
  public func scrollToBottom() { request = .bottom }
  public func scroll(to offset: Float) { request = .offset(offset) }
  public func scrollToVisible(_ rect: Rect) { request = .visible(rect) }
}

final class UniformRowIdentity: Equatable {
  let ids: Any
  let keys: [StructuralKey]
  let indices: [StructuralKey: Int]

  init<ID: Hashable & Sendable>(ids: [ID]) {
    self.ids = ids
    keys = ids.map { StructuralKey($0) }
    var indices: [StructuralKey: Int] = [:]
    indices.reserveCapacity(keys.count)
    for (index, key) in keys.enumerated() {
      precondition(indices.updateValue(index, forKey: key) == nil, "Duplicate lazy collection element ID")
    }
    self.indices = indices
  }

  static func == (lhs: UniformRowIdentity, rhs: UniformRowIdentity) -> Bool { lhs === rhs }
}
