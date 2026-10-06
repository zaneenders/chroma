public struct TextID: Hashable, Sendable {
  private let key: StructuralKey

  public init(_ value: some Hashable & Sendable) { key = StructuralKey(value) }
}

public struct TextDocument: Equatable, Sendable {
  public struct Run: Equatable, Sendable {
    public let id: TextID
    public let text: String
    public let separator: String

    public init(id: TextID, text: String, separator: String = "") {
      self.id = id
      self.text = text
      self.separator = separator
    }
  }

  public struct Position: Equatable, Sendable {
    public let run: TextID
    public let offset: Int

    public init(run: TextID, offset: Int) {
      self.run = run
      self.offset = offset
    }
  }

  public struct Selection: Equatable, Sendable {
    public let document: TextID
    public let anchor: Position
    public var active: Position

    public init(document: TextID, anchor: Position, active: Position) {
      self.document = document
      self.anchor = anchor
      self.active = active
    }
  }

  public let id: TextID
  public let revision: UInt64
  public let runs: [Run]
  private let indices: [TextID: Int]

  public init(id: TextID, revision: UInt64 = 0, runs: [Run]) {
    self.id = id
    self.revision = revision
    self.runs = runs
    indices = Dictionary(uniqueKeysWithValues: runs.enumerated().map { ($0.element.id, $0.offset) })
  }

  func index(of position: Position) -> Int? {
    guard let index = indices[position.run], (0...runs[index].text.count).contains(position.offset) else { return nil }
    return index
  }

  func bounds(of selection: Selection) -> (lower: Position, upper: Position, indices: ClosedRange<Int>)? {
    guard selection.document == id, let a = index(of: selection.anchor), let b = index(of: selection.active) else {
      return nil
    }
    let forward = a < b || (a == b && selection.anchor.offset <= selection.active.offset)
    return (
      forward ? selection.anchor : selection.active, forward ? selection.active : selection.anchor,
      min(a, b)...max(a, b)
    )
  }

  public func text(in selection: Selection) -> String? {
    guard let bounds = bounds(of: selection) else { return nil }
    return bounds.indices.map { index in
      let run = runs[index]
      let lower = index == bounds.indices.lowerBound ? bounds.lower.offset : 0
      let upper = index == bounds.indices.upperBound ? bounds.upper.offset : run.text.count
      return String(Array(run.text)[lower..<upper]) + (index < bounds.indices.upperBound ? run.separator : "")
    }.joined()
  }

  func range(in run: TextID, selection: Selection) -> Range<Int>? {
    guard let bounds = bounds(of: selection), let index = indices[run], bounds.indices.contains(index) else {
      return nil
    }
    let lower = index == bounds.indices.lowerBound ? bounds.lower.offset : 0
    let upper = index == bounds.indices.upperBound ? bounds.upper.offset : runs[index].text.count
    return lower..<upper
  }
}

struct TextRunReference: Equatable {
  let document: TextID
  let run: TextID
  var offset: Int = 0
}

extension Block {
  public func textDocument(_ document: TextDocument) -> some Block {
    DocumentBlock(content: self, document: document)
  }

  public func textRun(_ id: TextID, offset: Int = 0) -> some Block {
    precondition(offset >= 0)
    return DocumentRunBlock(content: self, id: id, offset: offset)
  }
}

private struct DocumentBlock: LayoutPreparingBlock {
  let content: any Block
  let document: TextDocument
  var preservesContentIdentity: Bool { true }

  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    var context = context
    context.textDocumentID = document.id
    context.textRunID = nil
    context.textRunOffset = 0
    let child = BlockEngine.prepare(content, context: context)
    return BlockEngine.Resolved(
      child: child,
      register: { rect in
        precondition(context.interaction.building.documents[document.id] == nil, "Duplicate text document ID")
        context.interaction.building.documents[document.id] = document
        child.register(in: rect)
      },
      paint: child.paint)
  }
}

private struct DocumentRunBlock: LayoutPreparingBlock {
  let content: any Block
  let id: TextID
  let offset: Int
  var preservesContentIdentity: Bool { true }

  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    var context = context
    context.textRunID = id
    context.textRunOffset = offset
    return BlockEngine.prepare(content, context: context)
  }
}
