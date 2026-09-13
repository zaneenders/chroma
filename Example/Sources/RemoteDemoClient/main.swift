import Chroma
import Foundation
import RemoteMetalClient

@main
struct RemoteDemoClient {
  @MainActor
  static func main() throws {
    #if DEBUG
    print("Performance warning: debug build; use -c release on both client and daemon.")
    #endif
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.contains("--help") || arguments.contains("-h") {
      print("usage: RemoteDemoClient [host] [port] [fps]")
      print("example: RemoteDemoClient 192.168.1.42 9328 30")
      return
    }
    let host = arguments.first ?? "127.0.0.1"
    let port = arguments.dropFirst().first.flatMap(Int.init) ?? 9328
    let fps = arguments.dropFirst(2).first.flatMap(Double.init) ?? 30

    let client = try RemoteMetalClient(
      size: Size(width: 800, height: 520), title: "Chroma Remote Client — \(host)")
    print("Connecting to \(host):\(port), requesting up to \(fps) fps")
    try client.connect(host: host, port: port, framesPerSecond: fps)
    client.run()
  }
}
