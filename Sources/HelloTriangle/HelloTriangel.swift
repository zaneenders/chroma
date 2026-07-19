import AppKit
import Metal
import MetalKit

@main
struct HelloTriangle {
  private enum Key: UInt16 {
    case a = 0
    case s = 1
    case d = 2
    case w = 13
    case q = 12
    case e = 14
  }

  public static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    view.device = MTLCreateSystemDefaultDevice()
    view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)

    guard let renderer = Renderer(view: view) else {
      fatalError("Metal requires Apple Silicon or supported GPU.")
    }
    view.delegate = renderer

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Hello Triangle"
    window.contentView = view
    window.center()
    window.makeKeyAndOrderFront(nil)

    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let handled: Bool
      switch Key(rawValue: event.keyCode) {
      case .w:
        renderer.offsetY += 0.05
        handled = true
      case .s:
        renderer.offsetY -= 0.05
        handled = true
      case .a:
        renderer.offsetX -= 0.05
        handled = true
      case .d:
        renderer.offsetX += 0.05
        handled = true
      case .q:
        renderer.rotation += 0.05
        handled = true
      case .e:
        renderer.rotation -= 0.05
        handled = true
      default:
        handled = false
      }
      return handled ? nil : event
    }

    app.activate(ignoringOtherApps: true)
    app.run()
  }
}
