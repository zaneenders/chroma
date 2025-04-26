/// Wraps a Value so that it can be viewed and mutated in other ``Block``s.
@propertyWrapper
public struct Binding<Value> {

  var get: () -> Value
  var set: (Value) -> Void

  public var wrappedValue: Value {
    get {
      get()
    }
    nonmutating set {
      return set(newValue)
    }
  }

  public var projectedValue: Binding<Value> {
    Binding(get: get, set: set)
  }
}
