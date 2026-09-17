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
