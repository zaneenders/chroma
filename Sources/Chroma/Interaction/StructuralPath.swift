struct StructuralPath: Hashable, Sendable {
  enum Segment: Hashable, Sendable {
    case key(StructuralKey)
    case slot(Int)
    case branch(Int)
    case background(Int)
    case component(ObjectIdentifier)
  }

  // Shallow paths are cheaper as small contiguous values. Longer paths share their
  // immutable prefix instead of copying every ancestor at each scope extension.
  static let shortPathLimit = 32

  enum Storage: Sendable {
    case short([Segment])
    case long(Node)

    var count: Int {
      switch self {
      case .short(let segments): segments.count
      case .long(let node): node.count
      }
    }

    var tail: Node? {
      if case .long(let node) = self { node } else { nil }
    }

    func hash(into hasher: inout Hasher) {
      switch self {
      case .short(let segments): hasher.combine(segments)
      case .long(let node): hasher.combine(node.fingerprint)
      }
    }
  }

  // Nodes contain identity values only, never resolved blocks, callbacks, geometry,
  // or interaction state. There is no interning table or cross-frame tree cache.
  final class Node: Sendable {
    let parent: Storage
    let segment: Segment
    let count: Int
    // A process-local hash accelerator, never proof of identity.
    let fingerprint: Int

    init(parent: Storage, segment: Segment) {
      self.parent = parent
      self.segment = segment
      count = parent.count + 1
      var hasher = Hasher()
      parent.hash(into: &hasher)
      hasher.combine(segment)
      fingerprint = hasher.finalize()
    }
  }

  private var storage: Storage = .short([])
  var tail: Node? { storage.tail }

  mutating func append(_ segment: Segment) {
    switch storage {
    case .short(var segments) where segments.count < Self.shortPathLimit:
      segments.append(segment)
      storage = .short(segments)
    default:
      storage = .long(Node(parent: storage, segment: segment))
    }
  }

  mutating func append(contentsOf segments: [Segment]) {
    guard !segments.isEmpty else { return }
    var shortCount = 0
    if case .short(var prefix) = storage {
      shortCount = min(Self.shortPathLimit - prefix.count, segments.count)
      if shortCount > 0 {
        prefix.append(contentsOf: segments.prefix(shortCount))
        storage = .short(prefix)
      }
    }
    for segment in segments.dropFirst(shortCount) { append(segment) }
  }

  // Materialization is for diagnostics/tests. Normal long-path extension and
  // hashing never flatten a path or copy its ancestor segments.
  var segments: [Segment] {
    if case .short(let segments) = storage { return segments }
    var result: [Segment] = []
    result.reserveCapacity(storage.count)
    var cursor = storage
    while case .long(let node) = cursor {
      result.append(node.segment)
      cursor = node.parent
    }
    if case .short(let prefix) = cursor { result.append(contentsOf: prefix.reversed()) }
    return result.reversed()
  }

  func allSatisfy(_ predicate: (Segment) -> Bool) -> Bool {
    Self.allSatisfy(storage, predicate)
  }

  private static func allSatisfy(_ storage: Storage, _ predicate: (Segment) -> Bool) -> Bool {
    switch storage {
    case .short(let segments): segments.allSatisfy(predicate)
    case .long(let node): predicate(node.segment) && allSatisfy(node.parent, predicate)
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    if case .long(let left) = lhs.storage, case .long(let right) = rhs.storage {
      if left === right { return true }
      guard left.count == right.count, left.fingerprint == right.fingerprint else { return false }
    }
    return equalStorage(lhs.storage, rhs.storage)
  }

  // Tail recursion lets optimized code borrow ancestor references instead of
  // retaining/releasing both nodes on every iteration of an owning cursor loop.
  private static func equalStorage(_ left: Storage, _ right: Storage) -> Bool {
    switch (left, right) {
    case (.short(let left), .short(let right)):
      return left == right
    case (.long(let left), .long(let right)):
      if left === right { return true }
      guard left.segment == right.segment else { return false }
      return equalStorage(left.parent, right.parent)
    default:
      return false
    }
  }

  func hash(into hasher: inout Hasher) { storage.hash(into: &hasher) }
}

struct ScopedBlock: Block {
  let content: any Block
  let path: [StructuralPath.Segment]

  var body: Never { fatalError("ScopedBlock is resolved by BlockEngine") }
}

struct StructuralKey: Hashable, Sendable {
  let value: any Hashable & Sendable

  init(_ value: some Hashable & Sendable) { self.value = value }

  static func == (lhs: Self, rhs: Self) -> Bool {
    ObjectIdentifier(type(of: lhs.value)) == ObjectIdentifier(type(of: rhs.value))
      && AnyHashable(lhs.value) == AnyHashable(rhs.value)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(type(of: value)))
    hasher.combine(AnyHashable(value))
  }
}

protocol KeyedBlockCollection: Block {
  var keyedContent: TupleBlock { get }
}

extension Block {
  public func id(_ key: some Hashable & Sendable) -> some Block {
    ScopedBlock(content: self, path: [.key(StructuralKey(key))])
  }
}
