import BasicContainers
import ContainersPreview
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
  @ObservationIgnored private var uniformIdentityRevision: UInt64?

  func rowIdentity<Data: RandomAccessCollection>(
    for data: Data, identityRevision: UInt64? = nil
  ) -> TypedUniformRowIdentity<Data.Element.ID>
  where Data.Element: Identifiable, Data.Element.ID: Sendable {
    if let cached = uniformRowIdentity as? TypedUniformRowIdentity<Data.Element.ID> {
      // A supplied revision is the caller's promise that ID values and order are unchanged.
      // Row values and callbacks are never retained here.
      if let identityRevision, uniformIdentityRevision == identityRevision, cached.keys.count == data.count {
        return cached
      }
      if cached.matches(data) {
        uniformIdentityRevision = identityRevision
        return cached
      }
    }
    let identity = TypedUniformRowIdentity(data: data)
    uniformRowIdentity = identity
    uniformIdentityRevision = identityRevision
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

class UniformRowIdentity: Equatable {
  let keys: [StructuralKey]
  let indices: [StructuralKey: Int]

  init(keys: [StructuralKey]) {
    self.keys = keys
    var indices: [StructuralKey: Int] = [:]
    indices.reserveCapacity(keys.count)
    for (index, key) in keys.enumerated() {
      precondition(indices.updateValue(index, forKey: key) == nil, "Duplicate lazy collection element ID")
    }
    self.indices = indices
  }

  static func == (lhs: UniformRowIdentity, rhs: UniformRowIdentity) -> Bool { lhs === rhs }
}

final class TypedUniformRowIdentity<ID: Hashable & Sendable>: UniformRowIdentity {
  let ids: RigidArray<ID>

  init<Data: RandomAccessCollection>(data: Data) where Data.Element: Identifiable, Data.Element.ID == ID {
    let ids = RigidArray(copying: data.lazy.map { $0.id })
    let keys = ids.indices.map { StructuralKey(ids[$0]) }
    self.ids = ids
    super.init(keys: keys)
  }

  func matches<Data: RandomAccessCollection>(_ data: Data) -> Bool
  where Data.Element: Identifiable, Data.Element.ID == ID {
    Self.matches(ids, data: data)
  }

  // Borrow the stored owner explicitly; Swift 6.4 cannot extend its property borrow through the iterator call.
  private static func matches<Data: RandomAccessCollection>(_ ids: borrowing RigidArray<ID>, data: Data) -> Bool
  where Data.Element: Identifiable, Data.Element.ID == ID {
    guard ids.count == data.count else { return false }
    if let equal = data.withContiguousStorageIfAvailable({ buffer in
      // The collection keeps this storage alive; the borrowed span never leaves this closure.
      ids.span.elementsEqual(unsafe buffer.span, by: { $0 == $1.id })
    }) {
      return equal
    }
    return ids.makeBorrowingIterator().elementsEqual(
      BorrowingIteratorAdapter(iterator: data.makeIterator()), by: { $0 == $1.id })
  }
}
