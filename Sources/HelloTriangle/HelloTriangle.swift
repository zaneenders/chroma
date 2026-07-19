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

// MARK: - Layout configuration

private let margin: Float = 16
private let headerHeight: Float = 48
private let statusHeight: Float = 32
private let panelPad: Float = 16
private let itemH: Float = 36  // standard item height
private let spacing: Float = 10
private let demoTextScale: Float = 2

// MARK: - Colors

private let bgColor = Color(r: 0.08, g: 0.09, b: 0.13, a: 1)
private let panelBg = Color(r: 0.10, g: 0.11, b: 0.16, a: 1)
private let headerBg = Color(r: 0.12, g: 0.14, b: 0.22, a: 1)
private let statusBg = Color(r: 0.06, g: 0.20, b: 0.12, a: 1)
private let borderDim = Color(r: 0.22, g: 0.22, b: 0.32, a: 1)
private let borderAccent = Color(r: 0.28, g: 0.44, b: 0.72, a: 1)
private let btnIdle = Color(r: 0.18, g: 0.20, b: 0.30, a: 1)
private let btnHover = Color(r: 0.25, g: 0.28, b: 0.42, a: 1)
private let btnPress = Color(r: 0.12, g: 0.14, b: 0.20, a: 1)
private let textSecondary = Color(r: 0.5, g: 0.5, b: 0.6, a: 1)
private let accentColor = Color(r: 0.3, g: 0.6, b: 1.0, a: 1)
private let greenColor = Color(r: 0.3, g: 0.8, b: 0.4, a: 1)
private let redColor = Color(r: 0.9, g: 0.3, b: 0.3, a: 1)
private let yellowColor = Color(r: 1, g: 0.85, b: 0.25, a: 1)
private let orangeColor = Color(r: 1, g: 0.55, b: 0.15, a: 1)

// MARK: - Helpers

/// Move the draw cursor down and return its position.
private func nextLine(_ cursor: inout Float, height: Float = itemH) -> Float {
  let y = cursor
  cursor += height + spacing
  return y
}

/// Draw a labelled button (visual only, no interaction yet).
private func drawButton(_ dl: inout DrawList, label: String, x: Float, y: Float, w: Float, color: Color) {
  let r = Rect(origin: Point(x: x, y: y), size: Size(width: w, height: itemH))
  dl.fillRect(r, color: color)
  dl.strokeRect(r, width: 1, color: borderDim)
  dl.text(label, at: Point(x: x + 12, y: y + 8), color: .white, scale: demoTextScale)
}

/// Draw a labelled checkbox (visual only).
private func drawCheck(_ dl: inout DrawList, label: String, x: Float, y: Float, checked: Bool, color: Color) {
  let boxSize: Float = 24
  let box = Rect(origin: Point(x: x, y: y + 6), size: Size(width: boxSize, height: boxSize))
  dl.fillRect(box, color: checked ? color : btnIdle)
  dl.strokeRect(box, width: 1, color: checked ? color : borderDim)
  if checked {
    dl.text("+", at: Point(x: x + 6, y: y + 8), color: .white, scale: demoTextScale)
  }
  dl.text(label, at: Point(x: x + boxSize + 10, y: y + 8), color: .white, scale: demoTextScale)
}

/// Draw a coloured swatch square.
private func drawSwatch(_ dl: inout DrawList, x: Float, y: Float, size: Float, color: Color, label: String) {
  let r = Rect(origin: Point(x: x, y: y), size: Size(width: size, height: size))
  dl.fillRect(r, color: color)
  dl.strokeRect(r, width: 1, color: borderDim)
  dl.text(label, at: Point(x: x, y: y + size + 6), color: textSecondary, scale: demoTextScale)
}

// MARK: - Main draw function

/// A richer demo: header bar, left sidebar with widgets, ASCII specimen panel,
/// right panel with stats/swatches, and a status bar — all drawn through the
/// immediate-mode draw list.
private func buildSpecimen(_ drawList: inout DrawList, viewport: Size) {
  // ---- background fill ----
  drawList.fillRect(Rect(origin: .zero, size: viewport), color: bgColor)

  let vw = viewport.width
  let vh = viewport.height

  // ---- header bar ----
  let headerRect = Rect(origin: .zero, size: Size(width: vw, height: headerHeight))
  drawList.fillRect(headerRect, color: headerBg)
  drawList.strokeRect(
    Rect(origin: Point(x: 0, y: headerHeight), size: Size(width: vw, height: 1)),
    width: 1, color: borderAccent
  )
  drawList.text(
    "swift-wayland  —  Immediate-Mode GUI Demo",
    at: Point(x: margin, y: 12),
    color: accentColor,
    scale: demoTextScale
  )

  // ---- status bar ----
  let statusY = vh - statusHeight
  let statusRect = Rect(origin: Point(x: 0, y: statusY), size: Size(width: vw, height: statusHeight))
  drawList.fillRect(statusRect, color: statusBg)
  drawList.strokeRect(
    Rect(origin: Point(x: 0, y: statusY), size: Size(width: vw, height: 1)),
    width: 1, color: borderAccent
  )
  drawList.text(
    "FPS: --   API: Metal   Backend: macOS   Viewport: \(Int(viewport.width))x\(Int(viewport.height))",
    at: Point(x: margin, y: statusY + 8),
    color: greenColor,
    scale: demoTextScale
  )

  let bodyTop = headerHeight + margin
  let bodyBottom = statusY - margin

  // ==== LEFT SIDEBAR ====
  let sidebarW: Float = 300
  let sidebarX = margin
  let sidebarRect = Rect(
    origin: Point(x: sidebarX, y: bodyTop),
    size: Size(width: sidebarW, height: bodyBottom - bodyTop)
  )
  drawList.fillRect(sidebarRect, color: panelBg)
  drawList.strokeRect(sidebarRect, width: 1, color: borderDim)

  var cy = bodyTop + panelPad
  let sx = sidebarX + panelPad
  let sw = sidebarW - 2 * panelPad

  drawList.text("CONTROLS", at: Point(x: sx, y: cy), color: textSecondary, scale: demoTextScale)
  cy += itemH + spacing * 2

  // Buttons
  drawButton(&drawList, label: "  New Project", x: sx, y: nextLine(&cy), w: sw, color: btnIdle)
  drawButton(&drawList, label: "  Open...", x: sx, y: nextLine(&cy), w: sw, color: btnIdle)
  drawButton(&drawList, label: "  Save", x: sx, y: nextLine(&cy), w: sw, color: btnIdle)

  cy += spacing
  drawList.text("OPTIONS", at: Point(x: sx, y: cy), color: textSecondary, scale: demoTextScale)
  cy += itemH + spacing * 2

  drawCheck(&drawList, label: "Wireframe", x: sx, y: nextLine(&cy), checked: true, color: accentColor)
  drawCheck(&drawList, label: "Grid", x: sx, y: nextLine(&cy), checked: true, color: accentColor)
  drawCheck(&drawList, label: "Axis", x: sx, y: nextLine(&cy), checked: false, color: accentColor)
  drawCheck(&drawList, label: "Stats", x: sx, y: nextLine(&cy), checked: true, color: accentColor)

  cy += spacing
  drawList.text("COLORS", at: Point(x: sx, y: cy), color: textSecondary, scale: demoTextScale)
  cy += itemH + spacing * 2
  let swatchSize: Float = 30
  let swatchColumnGap: Float = 88
  let swatchRowGap: Float = 60
  drawSwatch(&drawList, x: sx, y: cy, size: swatchSize, color: accentColor, label: "Blue")
  drawSwatch(&drawList, x: sx + swatchColumnGap, y: cy, size: swatchSize, color: greenColor, label: "Green")
  drawSwatch(&drawList, x: sx + 2 * swatchColumnGap, y: cy, size: swatchSize, color: redColor, label: "Red")
  drawSwatch(&drawList, x: sx, y: cy + swatchRowGap, size: swatchSize, color: yellowColor, label: "Yellow")
  drawSwatch(&drawList, x: sx + swatchColumnGap, y: cy + swatchRowGap, size: swatchSize, color: orangeColor, label: "Orange")
  drawSwatch(
    &drawList,
    x: sx + 2 * swatchColumnGap,
    y: cy + swatchRowGap,
    size: swatchSize,
    color: Color(r: 0.7, g: 0.3, b: 0.9, a: 1),
    label: "Purple"
  )

  // ==== RIGHT PANELS ====
  let rightX = sidebarX + sidebarW + margin
  let rightW = vw - rightX - margin
  let rightRect = Rect(
    origin: Point(x: rightX, y: bodyTop),
    size: Size(width: rightW, height: bodyBottom - bodyTop)
  )
  drawList.fillRect(rightRect, color: panelBg)
  drawList.strokeRect(rightRect, width: 1, color: borderDim)

  // ASCII specimen panel (top half of right)
  let asciiPrintableRows: [[UInt8]] = stride(from: 0x20, through: 0x70, by: 0x10).map { first in
    let last = min(first + 0x0f, 0x7e)
    let label = Array(String(format: "%02X  ", first).utf8)
    return label + (first...last).map(UInt8.init)
  }
  let asciiLines = [Array("5x7  PRINTABLE  ASCII  20..7E".utf8)] + asciiPrintableRows
  let metrics = FontMetrics()

  let specimenPad: Float = panelPad
  let availW = rightW - 2 * specimenPad
  let availH = bodyBottom - bodyTop - 2 * specimenPad
  let longestAsciiLine = Float(asciiLines.map(\.count).max() ?? 1)
  let wScale = availW / (longestAsciiLine * metrics.cellAdvance)
  let hScale = availH / (Float(asciiLines.count) * metrics.lineAdvance)
  let asciiScale = max(1, min(3, floor(min(wScale, hScale))))

  for (row, bytes) in asciiLines.enumerated() {
    let pos = Point(
      x: rightX + specimenPad,
      y: bodyTop + specimenPad + Float(row) * metrics.lineAdvance * asciiScale
    )
    drawList.text(
      String(decoding: bytes, as: UTF8.self),
      at: pos,
      color: row == 0 ? yellowColor : .white,
      scale: asciiScale
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
