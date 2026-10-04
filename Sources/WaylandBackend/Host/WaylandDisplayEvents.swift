import CWaylandClient
import Glibc

@diagnose(
  StrictMemorySafety, as: ignored,
  reason: "The caller owns the Wayland display; read preparation is completed or cancelled before returning."
)
package enum WaylandDisplayEvents {
  package static func dispatchAvailable(_ display: OpaquePointer) -> Int32 {
    // EGL can read the socket between the DispatchSource notification and this call.
    // Dispatch queued events, then prepare a read before checking current readiness.
    while unsafe wl_display_prepare_read(display) != 0 {
      guard unsafe wl_display_dispatch_pending(display) != -1 else { return -1 }
    }

    var descriptor = pollfd(fd: unsafe wl_display_get_fd(display), events: Int16(POLLIN), revents: 0)
    let ready = unsafe poll(&descriptor, 1, 0)
    if ready <= 0 {
      let pollError = errno
      unsafe wl_display_cancel_read(display)
      if ready < 0 && pollError != EINTR { return -1 }
      return unsafe wl_display_dispatch_pending(display)
    }
    guard descriptor.revents & Int16(POLLIN | POLLERR | POLLHUP) != 0 else {
      unsafe wl_display_cancel_read(display)
      return -1
    }
    guard unsafe wl_display_read_events(display) != -1 else { return -1 }
    return unsafe wl_display_dispatch_pending(display)
  }
}
