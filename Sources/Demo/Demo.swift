import Logging  // import for overloading the log level.
import Scribe
import SystemPackage  // import for optional logPath overload

@main
/// The entry and configuration point of your ``Scribe``.
struct Demo: Scribe {
  // Both of the following overloads can be removed or changed.

  // Optional overload for the logPath
  let logPath: FilePath = FilePath("scribe.log")
  // Optional overload for the logLevel
  let logLevel: Logger.Level = .debug

  // Entry point of your AST
  var window: some Window {
    TerminalWindow {
      NestedAsyncUpdate()
    }
    // Adds Mode to @Environment to be accessed through out the Block layers.
    .environment(Mode())
    // Override the default listener listener function to configure your own
    // movement commands.
    .register { input, container in
      switch input {
      case .lowercaseL:
        container.in()
      case .lowercaseS:
        container.out()
      case .lowercaseJ:
        container.down()
      case .lowercaseF:
        container.up()
      default:
        return input
      }
      return nil  // consume movement commands from being propagated
    }
  }
}

/// Here is a rough diagram of the demo's Entry AST that you are navigating.
///                                  Entry
///                                    │
///                                    │
///          ┌────────────────┬───_TupleBlock────┬───────────────┐
///          │                │                  │               │
///    Modified<String> Modified<String>   Modified<String>   Nested
///          │                │                  │               │
///       String           String             String          String
///          │                │                  │               │
/// Hello, I am Scribe. Zane was here :0 Job running: ready    Hello
struct Entry: Block {
  @Environment(Mode.self) var inputMode
  let storage = HeapObject()
  // ``@State`` is used for simple variables that can be modified at run time
  // by user interaction from the `.bind` function or async task.
  @State var running: RunningState = .ready
  @State var count = 0
  @State var message: String = "Hello"
  var layer: some Block {
    storage.message.bind { selected, key in
      if selected && key == .lowercaseI {
        // Mutating an object.
        switch inputMode.mode {
        case .input:
          inputMode.mode = .movement
        case .movement:
          inputMode.mode = .input
        }
        storage.message += "!"
        message += "#"
      }
    }
    "Zane was here :\(count)".bind { selected, key in
      if selected && key == .lowercaseE {
        // Basic counter
        count += 1
      }
    }
    "Job running: \(running)".bind { selected, key in
      if selected && key == .lowercaseI {
        self.longRunningTask()
      }
    }
    Nested(text: $message, count: $count)
  }

  // This is an example of a basic async task and update to the UI to display
  // if the task is still running. More complex states could be displayed by
  // extending ``RunningState``.
  func longRunningTask() {
    self.running = .running
    message = "\(running)"
    Task {
      self.running = await Worker.shared.performWork(with: .seconds(1))
      message = "\(running)"
    }
  }
}

/// This is an example of using an ``@Binding`` variable passed in from a
/// parent. This is useful if you only want the composed ``Block`` to display
/// or update based on another value.
struct Nested: Block {
  @Binding var text: String
  @Binding var count: Int
  var layer: some Block {
    "Nested[text: \(text)]"
    for i in 0..<count {
      "\(i)"
    }
  }
}

/// An example of a Heap allocated reference type object. If you are new to
/// Swift you can have the mental model that class's are reference types
/// located on the heap.
@Tracking
final class HeapObject {
  var message = "Hello, I am Scribe."
}

enum RunningState {
  case running
  case ready
}

final class Mode {

  enum InputMode {
    case movement
    case input
  }

  var mode: InputMode = .movement
}
