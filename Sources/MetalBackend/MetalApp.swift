#if METAL_BACKEND

import ImmediateGUI

/// An ``App`` that runs on the Metal backend.
///
/// Apply `@main` to a conforming type; `main()` comes from this extension:
///
/// ```swift
/// @main
/// struct HelloTriangle: MetalApp {
///   var body: some Block { Specimen() }
/// }
/// ```
public protocol MetalApp: App {}

extension MetalApp {
  @MainActor
  public static func main() {
    let app = Self()
    guard let renderer = MetalRenderer(size: app.windowSize) else {
      fatalError("Metal requires Apple Silicon or supported GPU.")
    }
    Self.run(on: renderer)
  }
}

#endif
