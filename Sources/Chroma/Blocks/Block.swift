public protocol Block {
  associatedtype Body: Block

  /// Describes the current UI. Evaluation must not perform application actions;
  /// layout may reuse the result within a traversal or evaluate it again for input registration.
  @MainActor var body: Body { get }
}

extension Never: Block {
  public var body: Never { fatalError("Never") }
}

extension String: Block {
  public var body: Text { Text(self) }
}
