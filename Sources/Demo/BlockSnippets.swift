import Chroma

/**
This file contains other examples and snippets. Mostly used for testing but provides a
starting point for building more complex interfaces.
*/

// This Block requires most of the resultBuilders to be used. Missing Optional
// right now.
struct All: Block {
  let items = ["Zane", "Was", "Here"]
  final class Storage {
    var condition = true
  }
  let store = Storage()
  var layer: some Block {
    "Button".bind { selected, key in
      if selected && key == .lowercaseI {
        store.condition.toggle()
      }
    }
    if store.condition {
      "A"
    } else {
      "B"
    }
    for item in items {
      item
    }
  }
}

struct TestNav: Block {
  var layer: some Block {
    Navigation {
      Item {
        "Top"
      } content: {
        BasicTupleBindedText()
      }
      Item {
        "Bottom"
      } content: {
        "Bottom Content"
      }
    }
  }
}

struct OptionalBlock: Block {
  var idk: String? = "Hello"
  var layer: some Block {
    "\(self)"
    if let hello = idk {
      hello
    }
  }
}

// Test case for moving down.
struct BasicTupleBindedText: Block {
  var layer: some Block {
    "Hello".bind { _, _ in
      // ignored
    }
    "Zane"
    "Enders".bind { _, _ in
      // ignored
    }
  }
}

// Very simple block that would be a Tuple and String blocks.
struct BasicTupleText: Block {
  var layer: some Block {
    "Hello"
    "Zane"
  }
}

struct HTest: Block {
  var layer: some Block {
    Group(.horizontal) {
      "Hello"
      "Zane"
    }
  }
}

struct HTest2: Block {
  var layer: some Block {
    Group(.horizontal) {
      "Hello"
      "Zane"
    }
    Group(.horizontal) {
      "Was"
      "Here"
    }
  }
}

// Used for testing selection and also to test merging two lists composed from arrays and tuple blocks.
struct SelectionBlock: Block {
  var layer: some Block {
    "Hello"
    "Zane"
    "was"
    "here"
    for i in 0..<3 {
      "\(i)"
    }
  }
}

// Test nested state
struct NestedState: Block {
  final class Storage {
    var count: Int = 0
  }
  let store = Storage()
  var layer: some Block {
    Nested(store: store)
  }

  struct Nested: Block {
    let store: Storage
    var layer: some Block {
      "\(store.count)".bind { selected, code in
        if selected && code == .lowercaseI {
          Log.warning("Clicked")
          store.count += 1
        }
      }
    }
  }
}

struct NestedAsyncUpdateHeapUpdate: Block {
  var layer: some Block {
    AsyncUpdateHeapUpdate()
  }
}

struct AsyncUpdateHeapUpdate: Block {
  static let delay = 100
  let storage = HeapObject()
  var layer: some Block {
    "\(storage.message)".bind { selected, key in
      if selected && key == .lowercaseI {
        update()
      }
    }
  }

  func update() {
    self.storage.message += "#"
    Task {
      _ = await Worker.shared.performWork(
        with: .milliseconds(AsyncUpdateHeapUpdate.delay))
      self.storage.message += "!"
    }
  }
}

@globalActor
// Making this a `@globalActor`` forces the work to be done off the main thread
// to help make sure that this API works for larger task.
actor Worker {
  static let shared = Worker()
  func performWork(with delay: Duration) async -> RunningState {
    try? await Task.sleep(for: delay)
    return .ready
  }
}
