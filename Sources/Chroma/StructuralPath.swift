struct StructuralPath: Hashable, Sendable {
  enum Segment: Hashable, Sendable {
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

protocol IdentityTransparentBlock: PrimitiveBlock {}
