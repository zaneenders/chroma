import CWaylandClient
import Glibc
import Testing

@testable import WaylandBackend

@diagnose(
  StrictMemorySafety, as: ignored,
  reason: "Tests use a socket pair to exercise libwayland without a compositor."
)
struct WaylandDisplayEventsTests {
  @Test func staleReadabilityDoesNotBlockAndCancelsPreparedRead() throws {
    var sockets: [Int32] = [0, 0]
    #expect(unsafe socketpair(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0, &sockets) == 0)
    let display = try #require(unsafe wl_display_connect_to_fd(sockets[0]))
    defer {
      unsafe wl_display_disconnect(display)
      _ = close(sockets[1])
    }

    // The notification may be stale because EGL already drained the socket.
    #expect(WaylandDisplayEvents.dispatchAvailable(display) == 0)
    // A second call also succeeds: the first must cancel its prepared read.
    #expect(WaylandDisplayEvents.dispatchAvailable(display) == 0)
  }

  @Test func disconnectedDisplayReportsFailure() throws {
    var sockets: [Int32] = [0, 0]
    #expect(unsafe socketpair(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0, &sockets) == 0)
    let display = try #require(unsafe wl_display_connect_to_fd(sockets[0]))
    defer { unsafe wl_display_disconnect(display) }
    _ = close(sockets[1])

    #expect(WaylandDisplayEvents.dispatchAvailable(display) == -1)
  }
}
