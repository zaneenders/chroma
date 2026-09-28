public protocol Block {
  associatedtype Body: Block

  @MainActor var body: Body { get }
}

extension Never: Block {
  public var body: Never { fatalError("Never") }
}

extension String: Block {
  public var body: Text { Text(self) }
}
