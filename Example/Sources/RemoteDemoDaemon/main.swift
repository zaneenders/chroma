import Chroma
import DemoBackend
import DemoContent
import Foundation
import HeadlessBackend
import RemoteProtocol
import RemoteServer

@main
struct RemoteDemoDaemon {
  @MainActor
  static func main() throws {
    #if DEBUG
    print("Performance warning: debug build; use -c release on both client and daemon.")
    #endif
    let benchmark = CommandLine.arguments.contains("--benchmark")
    var arguments = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--benchmark" }
    if arguments.contains("--help") || arguments.contains("-h") {
      print(
        "usage: RemoteDemoDaemon [bind-host] [port] [items] [--benchmark] [--capture-directory EXISTING_WRITABLE_DIRECTORY]"
      )
      print("example: RemoteDemoDaemon 0.0.0.0 9328 2000")
      return
    }
    let capture = try DemoCaptureConfiguration.parse(arguments: &arguments)
    let host = arguments.first ?? "127.0.0.1"
    let port = arguments.dropFirst().first.flatMap(Int.init) ?? 9328
    let itemCount = arguments.dropFirst(2).first.flatMap(Int.init) ?? 2_000
    // The remote display currently targets macOS, regardless of the daemon host.
    let demo = DemoApplication(itemCount: itemCount, shortcutModifier: .command, captureConfiguration: capture)

    if benchmark {
      let renderer = HeadlessRenderer(size: demo.windowSize)
      renderer.content = demo.body
      // Report cold layout separately from steady-state frames with cached row sizes.
      var total: TimeInterval = 0
      var commandCount = 0
      var encodeTotal: TimeInterval = 0
      var decodeTotal: TimeInterval = 0
      var wireBytes = 0
      var senderImages = RemoteImageCache()
      var receiverImages = RemoteImageCache()
      for frame in 0...60 {
        let started = ProcessInfo.processInfo.systemUptime
        let list = DrawList(commands: renderer.render().commands).culled(to: demo.windowSize)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        commandCount = list.commands.count
        let encodeStarted = ProcessInfo.processInfo.systemUptime
        var wire = try RemoteWire.encode(
          .frame(
            id: UInt64(frame), inputSequence: 0, viewport: demo.windowSize,
            commands: list.commands), images: &senderImages)
        let encodeElapsed = ProcessInfo.processInfo.systemUptime - encodeStarted
        wireBytes = wire.readableBytes
        let decodeStarted = ProcessInfo.processInfo.systemUptime
        let decoded = try RemoteWire.decode(from: &wire, images: &receiverImages)
        precondition(decoded != nil && wire.readableBytes == 0)
        let decodeElapsed = ProcessInfo.processInfo.systemUptime - decodeStarted
        if frame == 0 {
          print("cold draw \(milliseconds(elapsed)) ms | \(commandCount) commands")
        } else {
          total += elapsed
          encodeTotal += encodeElapsed
          decodeTotal += decodeElapsed
        }
      }
      print("mean draw \(milliseconds(total / 60)) ms | \(commandCount) commands | 60 frames")
      print(
        "mean wire encode \(milliseconds(encodeTotal / 60)) ms | decode \(milliseconds(decodeTotal / 60)) ms | \(wireBytes) bytes/frame")
      return
    }

    let server = DemoBackend.makeServer(for: demo)
    try server.start(host: host, port: port)
    print("Interactive performance scene: \(itemCount) animated shapes")
    print("Click the controls in the remote window or use j/f/d/k and Enter")
    server.run()
  }
}

private func milliseconds(_ seconds: Double) -> String {
  (seconds * 1000).formatted(
    .number.locale(Locale(identifier: "en_US_POSIX"))
      .grouping(.never).precision(.fractionLength(2)))
}
