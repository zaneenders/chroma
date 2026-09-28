import Testing
import HeadlessBackend

@testable import Chroma

@MainActor
struct WindowRuntimeTests {
  @Test func appBindingsReachTheHeadlessRuntime() throws {
    let host = HeadlessHost()
    try BoundApp().run(on: host)
    #expect(host.runtime.resolve(KeyboardInput(chord: KeyChord("j"), text: "j")) == .command(.navigation(.down)))
  }

  @Test func replacingBindingsChangesResolution() {
    let runtime = WindowRuntime()
    runtime.keyBindings = KeyBindings { bind("j", to: .navigation(.down)) }
    let input = KeyboardInput(chord: KeyChord("j"), text: "j")
    #expect(runtime.resolve(input) == .command(.navigation(.down)))
    runtime.keyBindings = KeyBindings { disable("j") }
    #expect(runtime.resolve(input) == nil)
  }

  @Test func observationPreservesHostRasterScale() {
    let runtime = WindowRuntime()
    let viewport = Size(width: 40, height: 30)
    var observations: [FrameObservation] = []
    runtime.frameObserver = { observations.append($0) }
    let list = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.observe(list, viewport: viewport)
    runtime.observe(list, viewport: viewport, rasterScale: Point(x: 2, y: 2))
    #expect(observations.count == 2)
    #expect(observations[0].rasterScale == nil)
    #expect(observations[1].rasterScale == Point(x: 2, y: 2))
    #expect(observations[1].viewport == viewport)
  }
}

private struct BoundApp: App {
  var keyBindings: KeyBindings { KeyBindings { bind("j", to: .navigation(.down)) } }
  var body: some Block { Text("Runtime") }
}
