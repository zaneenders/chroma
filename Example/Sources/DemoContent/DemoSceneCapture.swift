import Chroma
import Foundation
import Observation

@MainActor
@Observable
final class DemoSceneCapture {
  private(set) var status = "Ctrl+Shift+G: capture next frame (includes text/images)"
  private let configuration: DemoCaptureConfiguration

  init(configuration: DemoCaptureConfiguration) {
    self.configuration = configuration
    status = "Ctrl+Shift+G: capture to \(configuration.directory.path) (includes text/images)"
  }

  private var pending = false
  private var saving = false

  func request() {
    guard !pending && !saving else { return }
    pending = true
    status = "Scene capture requested"
  }

  func observe(_ frame: FrameObservation) {
    guard pending && !saving else { return }
    pending = false
    saving = true
    status = "Saving scene capture..."
    let directory = configuration.directory
    Task { [self] in
      let result = await Task.detached(priority: .utility) { () -> Result<URL, Error> in
        Result {
          let data = try SceneCapture.encode(frame)
          let url = directory.appendingPathComponent("scene-\(UUID().uuidString).chromacapture")
          guard
            FileManager.default.createFile(
              atPath: url.path, contents: data,
              attributes: [.posixPermissions: 0o600])
          else {
            throw CocoaError(.fileWriteUnknown)
          }
          return url
        }
      }.value
      saving = false
      switch result {
      case .success(let url):
        status = "Saved scene: \(url.lastPathComponent)"
        print("Scene capture saved: \(url.path)")
      case .failure(let error):
        status = "Scene capture failed: \(error)"
        print(status)
      }
    }
  }
}
