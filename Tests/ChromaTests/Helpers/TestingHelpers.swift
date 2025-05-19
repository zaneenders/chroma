import Testing

@testable import Chroma

func enableTestLogging(write_to_file: Bool = true) {
  enableLogging(
    file_path: "chroma.log", logLevel: .trace, tracing: false, write_to_file: write_to_file)
  clearLog("chroma.log")
}

// Helper functions to make creating test easier.
extension ChromaController {
  mutating func moveUp() {
    up()
  }
  mutating func moveDown() {
    down()
  }
  mutating func moveOut() {
    out()
  }
  mutating func moveIn() {
    `in`()
  }

  mutating func expectState(_ renderer: inout TestRenderer, expected: [String]) {
    self.observe(with: &renderer)
    let output = renderer.previousWalker.textObjects.map { $0.value }
    #expect(output.sorted() == expected.sorted())
  }

  // Helper for creating expected arrays
  mutating func printState(_ renderer: inout TestRenderer) {
    self.observe(with: &renderer)
    let output = renderer.previousWalker.textObjects.map { $0.value }
    print(output)
  }
}
