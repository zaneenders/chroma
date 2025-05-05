/// Wraps a Value so that it can be viewed and mutated in other ``Block``s.
@propertyWrapper
internal struct Binding<Value> {

  var get: () -> Value
  var set: (Value) -> Void

  internal var wrappedValue: Value {
    get {
      get()
    }
    nonmutating set {
      return set(newValue)
    }
  }

  internal var projectedValue: Binding<Value> {
    Binding(get: get, set: set)
  }
}
