import CWaylandClient
import Glibc

@diagnose(
  StrictMemorySafety, as: ignored,
  reason: "Wayland owns the display and its socket; a prepared read is consumed or cancelled before returning."
)
enum WaylandDisplayEvents {
  /// Drain queued events, but never wait for socket data on the UI thread.
  static func dispatchAvailable(_ display: OpaquePointer) -> Int32 {
    // EGL can read the socket between a DispatchSource notification and this call.
    // Dispatch its queued events before preparing another read.
    while unsafe wl_display_prepare_read(display) != 0 {
      if unsafe wl_display_dispatch_pending(display) == -1 { return -1 }
    }

    var descriptor = pollfd(fd: unsafe wl_display_get_fd(display), events: Int16(POLLIN), revents: 0)
    let ready = unsafe poll(&descriptor, 1, 0)
    if ready <= 0 {
      unsafe wl_display_cancel_read(display)
      if ready < 0 && errno != EINTR { return -1 }
    } else {
      // read_events completes the prepared read even on error. POLLHUP/POLLERR
      // also reach it so a disconnected compositor is reported normally.
      if unsafe wl_display_read_events(display) == -1 { return -1 }
    }
    return unsafe wl_display_dispatch_pending(display)
  }
}
