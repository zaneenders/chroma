#if WAYLAND_BACKEND

import CWaylandClient
import CWaylandCursor
import Foundation

/// Loads an arrow cursor from the system Xcursor theme and applies it via
/// `wl_pointer.set_cursor` when the pointer enters the window.
@MainActor
final class WaylandCursor {
  private var theme: OpaquePointer?
  private var cursor: UnsafeMutablePointer<wl_cursor>?
  private var surface: OpaquePointer?

  func setUp(compositor: OpaquePointer, shm: OpaquePointer) {
    guard surface == nil else { return }
    surface = unsafe wl_compositor_create_surface(compositor)
    let themeName = ProcessInfo.processInfo.environment["XCURSOR_THEME"] ?? "default"
    let themeSize = Int32(ProcessInfo.processInfo.environment["XCURSOR_SIZE"] ?? "") ?? 24
    theme = themeName.withCString { name in
      unsafe wl_cursor_theme_load(name, Int32(themeSize), shm)
    }
    guard let theme else { return }
    cursor = unsafe wl_cursor_theme_get_cursor(theme, "left_ptr")
    if cursor == nil {
      cursor = unsafe wl_cursor_theme_get_cursor(theme, "default")
    }
  }

  func apply(pointer: OpaquePointer, serial: UInt32) {
    guard let surface, let cursor, cursor.pointee.image_count > 0 else { return }
    guard let image = cursor.pointee.images[0] else { return }
    guard let buffer = unsafe wl_cursor_image_get_buffer(image) else { return }
    unsafe wl_surface_attach(surface, buffer, 0, 0)
    unsafe wl_surface_damage(surface, 0, 0, Int32(image.pointee.width), Int32(image.pointee.height))
    unsafe wl_surface_commit(surface)
    unsafe wl_pointer_set_cursor(
      pointer, serial, surface,
      Int32(image.pointee.hotspot_x), Int32(image.pointee.hotspot_y))
  }

  func cleanup() {
    if let surface { unsafe wl_surface_destroy(surface) }
    if let theme { unsafe wl_cursor_theme_destroy(theme) }
    surface = nil
    theme = nil
    cursor = nil
  }
}

#endif
