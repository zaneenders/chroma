struct StructuralPath: Hashable, Sendable {
  enum Segment: Hashable, Sendable {
    case key(StructuralKey)
    case slot(Int)
    case branch(Int)
    case background(Int)
    case component(ObjectIdentifier)
  }

  var segments: [Segment] = []
}

struct ScopedBlock: Block {
  let content: any Block
  let path: [StructuralPath.Segment]

  var body: Never { fatalError("ScopedBlock is resolved by BlockEngine") }
}

protocol IdentityTransparentBlock: PrimitiveBlock {
  var content: any Block { get set }
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
  /// Keys this subtree within its structural parent.
  ///
  /// Use this when the same position displays different logical content:
  ///
  /// ```swift
  /// ScrollView {
  ///   Text(document.content)
  /// }
  /// .id(document.id)
  /// ```
  ///
  /// Changing the key replaces the subtree's interaction identity, resetting
  /// editing, text selection, and scroll offsets. Returning to a previously
  /// removed key does not restore its state. Focus uses the normal fallback
  /// when the focused control is replaced.
  ///
  /// Keys are parent-scoped and type-sensitive, not global widget identifiers.
  /// An unchanged key does not preserve state after the subtree disappears.
  ///
  /// - Parameter key: A stable key for the logical content of this subtree.
  public func id(_ key: some Hashable & Sendable) -> some Block {
    ScopedBlock(content: self, path: [.key(StructuralKey(key))])
  }
}
