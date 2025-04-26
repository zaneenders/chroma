@MainActor
@propertyWrapper
public struct Environment<V> {
  private let key: ObjectIdentifier
  public init(_ key: V.Type) {
    self.key = ObjectIdentifier(key)
  }
  public var wrappedValue: V {
    get {
      EnvStorage.shared.storage[key]! as! V
    }
    set {
      EnvStorage.shared.storage[key] = newValue
    }
  }
}

@MainActor
private final class EnvStorage {
  static let shared: EnvStorage = EnvStorage()
  var storage: [ObjectIdentifier: Any] = [:]
}
