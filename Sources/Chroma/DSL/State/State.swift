/// The @``State`` type is a hack around swift mutability semantics allowing
/// computed variables like ``Block/component`` to mutate there containing structs.
@MainActor  // This forces ``State``
@propertyWrapper
public struct State<Value> {

  private let storage: Storage

  public init(wrappedValue: Value) {
    self.storage = Storage(wrappedValue)
  }

  public var wrappedValue: Value {
    get {
      storage.value
    }
    nonmutating set {
      storage.value = newValue
    }
  }

  public var projectedValue: Binding<Value> {
    Binding(
      get: {
        self.wrappedValue
      },
      set: { newValue in
        self.wrappedValue = newValue
      })
  }

  @MainActor
  private final class Storage {
    var value: Value
    init(_ value: Value) {
      self.value = value
    }
  }
}
