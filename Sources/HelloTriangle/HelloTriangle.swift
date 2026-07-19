#if METAL_BACKEND

import AppKit
import ImmediateGUI
import MetalBackend

@main
struct HelloTriangle {
  public static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    guard let renderer = MetalRenderer(frame: NSRect(x: 0, y: 0, width: 800, height: 600)) else {
      fatalError("Metal requires Apple Silicon or supported GPU.")
    }
    renderer.buildFrame = buildSpecimen

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Hello Triangle"
    window.contentView = renderer.contentView
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.activate(ignoringOtherApps: true)
    app.run()
  }
}

/// Draws a specimen containing every printable ASCII glyph (U+0020...U+007E).
/// Keeping this in the demo makes malformed, missing, or inconsistently aligned glyphs obvious.
private func buildSpecimen(_ drawList: inout DrawList, viewport: Size) {
  let printableRows: [[UInt8]] = stride(from: 0x20, through: 0x70, by: 0x10).map { first in
    let last = min(first + 0x0f, 0x7e)
    let label = Array(String(format: "%02X  ", first).utf8)
    return label + (first...last).map(UInt8.init)
  }
  let lines = [Array("5x7 PRINTABLE ASCII 20-7E".utf8)] + printableRows

  // Use an integer scale so each font pixel lands on an exact block of screen pixels.
  let metrics = FontMetrics()
  let margin: Float = 20
  let longestLine = Float(lines.map(\.count).max() ?? 1)
  let widthScale = (viewport.width - margin * 2) / (longestLine * metrics.cellAdvance)
  let heightScale = (viewport.height - margin * 2) / (Float(lines.count) * metrics.lineAdvance)
  let scale = max(1, min(4, floor(min(widthScale, heightScale))))

  for (row, bytes) in lines.enumerated() {
    let position = Point(x: margin, y: margin + Float(row) * metrics.lineAdvance * scale)
    drawList.text(
      String(decoding: bytes, as: UTF8.self),
      at: position,
      color: row == 0 ? .yellow : .white,
      scale: scale
    )
  }
}

#elseif WAYLAND_BACKEND

import WaylandBackend

@main
struct HelloTriangle {
  static func main() {
    // The Wayland backend is a stub; constructing it calls fatalError.
    _ = WaylandRenderer()
  }
}

#else
  #error("HelloTriangle requires a rendering backend: MetalBackend (enabled by default) or WaylandBackend.")
#endif
