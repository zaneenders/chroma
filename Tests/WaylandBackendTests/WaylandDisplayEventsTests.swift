import CWaylandClient
import Glibc
import Testing

@testable import WaylandBackend

@diagnose(StrictMemorySafety, as: ignored, reason: "Tests own the socket pair and Wayland display.")
struct WaylandDisplayEventsTests {
  @Test func staleReadNotificationDoesNotBlockOrLeavePreparedRead() throws {
    var sockets: [Int32] = [-1, -1]
    try #require(socketpair(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0, &sockets) == 0)
    defer { close(sockets[1]) }
    let connection = unsafe wl_display_connect_to_fd(sockets[0])
    let display = unsafe try #require(connection)
    defer { wl_display_disconnect(display) }

    // The peer is open but has no data, as after EGL consumes a read notification.
    #expect(WaylandDisplayEvents.dispatchAvailable(display) == 0)
    #expect(WaylandDisplayEvents.dispatchAvailable(display) == 0)
    // A successful prepare confirms the default queue is still empty.
    #expect(wl_display_prepare_read(display) == 0)
    wl_display_cancel_read(display)
  }

  @Test func disconnectedPeerReportsFailure() throws {
    var sockets: [Int32] = [-1, -1]
    try #require(socketpair(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0, &sockets) == 0)
    let connection = unsafe wl_display_connect_to_fd(sockets[0])
    let display = unsafe try #require(connection)
    defer { wl_display_disconnect(display) }
    close(sockets[1])
    #expect(WaylandDisplayEvents.dispatchAvailable(display) == -1)
  }
}
