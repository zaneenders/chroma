@MainActor
protocol StateProtocol {
  var storage: any StorageProtocol { get }
}

@MainActor
protocol StorageProtocol<Value> {
  associatedtype Value = Any
  var _stored: any Sendable { get nonmutating set }
  var box: Box<Value> { get nonmutating set }
}

@propertyWrapper
@available(*, deprecated, message: "Seeing what I can build without @State")
/*
Ok so doing async updates to this is more complicated than it's worth right now.
Instead of letting the project get stuck because of this I am going for a not as pretty DSL in favor of building something.
*/
@MainActor
internal struct State<Value: Sendable>: StateProtocol {
  private let _storage: Storage

  internal init(wrappedValue: Value) {
    self._storage = Storage(wrappedValue)
  }

  var storage: any StorageProtocol {
    _storage
  }

  internal var wrappedValue: Value {
    get {
      _storage.value
    }
    nonmutating set {
      _storage.value = newValue
    }
  }

  internal var projectedValue: Binding<Value> {
    Binding(
      get: {
        self.wrappedValue
      },
      set: { newValue in
        self.wrappedValue = newValue
      })
  }
}

extension State {
  @MainActor
  final class Storage: StorageProtocol {

    var box: Box<Value>

    init(_ value: Value) {
      self.box = Box(value)
    }

    var _stored: any Sendable {
      get {
        box.value
      }
      set {
        box.value = newValue as! Value
      }
    }

    var value: Value
    {
      get {
        box.value
      }
      set {
        box.value = newValue
      }
    }
  }
}

final class Box<Value> {

  var value: Value

  init(_ value: Value) {
    self.value = value
  }
}
