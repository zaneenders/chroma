// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "HelloTriangle",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "HelloTriangle",
      exclude: ["Shaders"],
      linkerSettings: [
        .unsafeFlags([
          "-framework", "Metal",
          "-framework", "MetalKit",
          "-framework", "AppKit",
        ])
      ],
      plugins: [
        .plugin(name: "MetalSourcePlugin")
      ]
    ),
    .executableTarget(name: "MetalSourceGenerator"),
    .plugin(
      name: "MetalSourcePlugin",
      capability: .buildTool(),
      dependencies: ["MetalSourceGenerator"]
    ),
  ]
)
