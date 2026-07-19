// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "HelloTriangle",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "HelloTriangle",
      linkerSettings: [
        .unsafeFlags([
          "-framework", "Metal",
          "-framework", "MetalKit",
          "-framework", "AppKit",
        ])
      ]
    )
  ]
)
