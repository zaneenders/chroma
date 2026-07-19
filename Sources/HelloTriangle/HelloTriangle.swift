import AppKit

@main
struct HelloTriangle {
  public static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    guard let renderer = MetalRenderer(frame: NSRect(x: 0, y: 0, width: 800, height: 600)) else {
      fatalError("Metal requires Apple Silicon or supported GPU.")
    }

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
