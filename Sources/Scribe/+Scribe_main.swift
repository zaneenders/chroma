extension Scribe {
  // The "main" function and main UI event loop of Scribe for now.
  public static func main() async {
    let scribe = self.init()
    enableLogging(
      file_path: scribe.logPath, logLevel: scribe.logLevel, tracing: false, write_to_file: true)
    clearLog(scribe.logPath)

    var renderer = TerminalRenderer()

    var block_container = ScribeController(scribe.window.entry)

    // Background render loop.
    let renderingLoop = Task {
      /*
      I have found doing pushed based updates to the screen a little tricky
      because of Swift concurrency model. So using a simple render loop for now.
      */
      while !Task.isCancelled {
        block_container.observe(with: &renderer)
        // ~30 FPS
        try? await Task.sleep(for: .milliseconds(33))
      }
    }

    let listener: InputListener? = scribe.window.listener

    do {
      input_loop: for try await byte in renderer.input {
        guard let code = AsciiKeyCode.decode(keyboard: byte) else {
          Log.warning("Could not decode: \(byte)")
          continue
        }
        /*
        This is kinda bad but does give me the idea of surfacing the shutdown
        sequence as an external API which could be cool.
        */
        if let listener {
          if let listenedCode = listener(code, &block_container) {
            switch listenedCode {
            case .ctrlC:
              renderingLoop.cancel()
              break input_loop
            default:
              block_container.action(listenedCode)
            }
          }
        } else {
          switch code {
          case .ctrlC:
            renderingLoop.cancel()
            break input_loop
          default:
            block_container.action(code)
          }
        }
      }
    } catch {
      Log.error("\(error.localizedDescription)")
    }

    // Restore the terminal config.
    renderer.close()
  }
}
