import Chroma

/**
This file contains other examples and snippets. Mostly used for testing but provides a
starting point for building more complex interfaces.
*/

// This Block requires most of the resultBuilders to be used. Missing Optional
// right now.
struct All: Block {
  let items = ["Zane", "Was", "Here"]
  @State var condition = true
  var layer: some Block {
    "Button".bind { selected, key in
      if selected && key == .lowercaseI {
        condition.toggle()
      }
    }
    if condition {
      "A"
    } else {
      "B"
    }
    for item in items {
      item
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

// Simple example of asynchronously updating the state from a
struct AsyncUpdateStateUpdate: Block {
  static let delay = 100
  @State var state: RunningState = .ready
  var layer: some Block {
    "\(state)".bind { selected, key in
      if selected && key == .lowercaseI {
        update()
      }
    }
  }

  func update() {
    self.state = .running
    Task {
      self.state = await Worker.shared.performWork(
        with: .milliseconds(AsyncUpdateStateUpdate.delay))
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
