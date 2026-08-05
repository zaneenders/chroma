import Chroma
import Foundation

enum DemoTab {
  case package
  case ascii
}

final class DemoState {
  var selectedTab: DemoTab = .package
  let packageSource = DemoState.loadPackageSource()
  let packageScrollController = ScrollViewController()
  var accent = Color(r: 0.20, g: 0.62, b: 0.98, a: 1)
  var accentName = "Blue"
  var wireframe = false
  var grid = true
  var axis = false
  var stats = true
  var name = ""
  var lastAction = "None"
  var actionCount = 0

  func record(_ action: String) {
    lastAction = action
    actionCount += 1
  }

  private static func loadPackageSource() -> String {
    let packageURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Package.swift")
    return (try? String(contentsOf: packageURL, encoding: .utf8))
      ?? "Could not load \(packageURL.path)"
  }
}
