import Chroma
import DemoContent
import RemoteServer

public enum DemoBackend {
  @MainActor
  public static func makeServer(for demo: DemoApplication) -> RemoteServer {
    let server = RemoteServer(size: demo.windowSize) { demo.body }
    server.frameObserver = demo.frameObserver
    server.keyBindings = demo.keyBindings
    return server
  }
}
