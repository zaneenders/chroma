import CWaylandClient
import CWaylandCursor
import Foundation

@diagnose(
  StrictMemorySafety, as: ignored,
  reason: "Wayland cursor pointers are borrowed from the owned theme and used only until cleanup on the main actor.")
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
    guard theme != nil, let surface, let cursor else { return }
    let value = unsafe cursor.pointee
    guard value.image_count > 0, let images = unsafe value.images,
      let image = unsafe images[0]
    else { return }
    let info = unsafe image.pointee
    guard let width = Int32(exactly: info.width), let height = Int32(exactly: info.height),
      let hotspotX = Int32(exactly: info.hotspot_x), let hotspotY = Int32(exactly: info.hotspot_y)
    else { return }
    guard let buffer = unsafe wl_cursor_image_get_buffer(image) else { return }
    unsafe wl_surface_attach(surface, buffer, 0, 0)
    unsafe wl_surface_damage(surface, 0, 0, width, height)
    unsafe wl_surface_commit(surface)
    unsafe wl_pointer_set_cursor(
      pointer, serial, surface,
      hotspotX, hotspotY)
  }

  func cleanup() {
    if let surface { unsafe wl_surface_destroy(surface) }
    if let theme { unsafe wl_cursor_theme_destroy(theme) }
    surface = nil
    theme = nil
    cursor = nil
  }
}
