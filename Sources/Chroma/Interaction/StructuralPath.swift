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

struct KeyedBlock: Block {
  let content: any Block
  let key: StructuralKey
  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    var context = context
    if case .slot = context.structuralPath.segments.last { context.structuralPath.segments.removeLast() }
    return buffer.emit(content, context: context.scoped([.key(key)]))
  }
}

extension Block {
  public func id(_ key: some Hashable & Sendable) -> some Block {
    KeyedBlock(content: self, key: StructuralKey(key))
  }
}
