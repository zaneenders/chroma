/// The @``State`` type is a hack around swift mutability semantics allowing
/// computed variables like ``Block/component`` to mutate there containing structs.
// This forces ``State``
@propertyWrapper
public struct State<Value: Sendable>: StateProtocol {

  private let _storage: Storage

  public init(wrappedValue: Value) {
    self._storage = Storage(wrappedValue)
  }

  var storage: any StorageProtocol {
    _storage
  }

  public var wrappedValue: Value {
    get {
      _storage.value
    }
    nonmutating set {
      _storage.value = newValue
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
}

extension State {

  final class Storage: StorageProtocol {

    private var _box: Box<Value>

    init(_ value: Value) {
      self._box = Box(value)
    }

    var box: any TrackingMarker {
      get {
        _box
      }
      set {
        _box = newValue as! Box<Value>
      }
    }

    var _stored: any Sendable {
      get {
        _box.value
      }
      set {
        _box.value = newValue as! Value
      }
    }

    var value: Value
    {
      get {
        _box.value
      }
      set {
        _box.value = newValue
      }
    }
  }

}

protocol StateProtocol {
  var storage: any StorageProtocol { get }
}

protocol StorageProtocol {
  var _stored: any Sendable { get nonmutating set }
  var box: any TrackingMarker { get nonmutating set }
}

@Tracking
private final class Box<Value> {

  init(_ value: Value) {
    self.value = value
  }

  var value: Value
}
