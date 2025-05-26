import Synchronization

final class Cache: Sendable {
  static let shared = Cache()
  let storage: Mutex<[String: Sendable]> = Mutex([:])
}

extension Block {

  internal func saveState(nodeKey: String) {
    let mirror = Mirror(reflecting: self)
    for (i, child) in mirror.children.enumerated() {
      if var state = child.value as? any StateProtocol {
        _saveState(hash(contents: "\(nodeKey)[\(i)]"), &state)
      }
    }
  }

  internal func restoreState(nodeKey: String) {
    let mirror = Mirror(reflecting: self)
    for (i, child) in mirror.children.enumerated() {
      if var state = child.value as? any StateProtocol {
        _restoreState(hash(contents: "\(nodeKey)[\(i)]"), &state)
      }
    }
  }
}

@MainActor
private func _saveState(_ key: String, _ state: inout some StateProtocol) {
  Cache.shared.storage.withLock { cache in
    let v = state.storage._stored
    _ChromaLog.warning("Saving: \(v)")
    cache[key] = v
  }
}

@MainActor
private func _restoreState(
  _ key: String, _ state: inout some StateProtocol
) {
  Cache.shared.storage.withLock { cache in
    if let v = cache[key] {
      state.storage._stored = v
      _ChromaLog.warning("Hit: \(v)")
    } else {
      _ChromaLog.error("Key: \(key) missing from cache: \(cache).")
    }
  }
}
