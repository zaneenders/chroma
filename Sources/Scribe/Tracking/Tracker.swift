import Synchronization

/*
This allows us to track the mutations and accesses of @State values and others if needed.
Which should enable the ability to diff updates as well as adding TrackingStorage to new
properties when they are created.
*/
typealias NodeKey = String
public final class Tracker: Sendable {
  static let shared = Tracker()
  // This makes accessing the cache expensive. So maybe the Tracker should parse
  // the tree and lock and unlock once.

  // The cache is used to save and restore values before rendering and after
  // mutation.
  let cache: Mutex<[NodeKey: any Sendable]>

  init() {
    self.cache = Mutex([:])
  }

  /// Called on each access to a ``@Tracked`` variable.
  public func access() {
    // Log.trace("\(#function)")
  }

  /// Called when a ``@Tracked`` variable is mutated.
  public func mutating(
    _ mutation: () -> Void
  ) {
    // Does this need to happen inside the lock?
    mutation()
    Log.trace("\(#function)")
  }
}

/// MARK: Save and restoring State
/*
Maybe the keys should be the location so I can remove un needed nodes?

We can use the child's position `i` as this isn't going ot move at runtime.
*/
extension Block {

  func saveState(nodeKey: NodeKey, _ tracker: Tracker) {
    Log.critical("SAVE")
    let mirror = Mirror(reflecting: self)
    for (i, child) in mirror.children.enumerated() {
      if var state = child.value as? any StateProtocol {
        let key = "\(nodeKey)[\(i)]"
        _saveState(key, &state, tracker)
      }
    }
  }

  func restoreState(nodeKey: NodeKey, _ tracker: Tracker) {
    Log.critical("RESTORE")
    let mirror = Mirror(reflecting: self)
    for (i, child) in mirror.children.enumerated() {
      if var state = child.value as? any StateProtocol {
        let key = "\(nodeKey)[\(i)]"
        _restoreState(key, &state, tracker)
      }
    }
  }
}

@MainActor
private func _saveState(_ key: NodeKey, _ state: inout some StateProtocol, _ tracker: Tracker) {
  let v = state.storage._stored
  tracker.cache.withLock { cache in
    cache[key] = v
  }
}

@MainActor
private func _restoreState(_ key: NodeKey, _ state: inout some StateProtocol, _ tracker: Tracker) {
  tracker.cache.withLock { cache in
    if let v = cache[key] {
      state.storage._stored = v
    }
  }
}

/// MARK: Setting the tracker pointer
extension Block {
  func updateTracker(_ tracker: Tracker) {
    let mirror = Mirror(reflecting: self)
    for child in mirror.children {
      if var state = child.value as? any StateProtocol {
        _setTracker(&state, tracker)
      }
      if var tracked = child.value as? any TrackingMarker {
        _setTracker(&tracked, tracker)
      }
    }
  }
}

@MainActor
private func _setTracker(_ tracked: inout some TrackingMarker, _ tracker: Tracker) {
  tracked._$_tracker = tracker
}

@MainActor
private func _setTracker(_ state: inout some StateProtocol, _ tracker: Tracker) {
  state.storage.box._$_tracker = tracker
}
