// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "HelloTriangle",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ImmediateGUI", targets: ["ImmediateGUI"]),
  ],
  targets: [
    .target(
      name: "ImmediateGUI",
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
    .executableTarget(
      name: "HelloTriangle",
      dependencies: ["ImmediateGUI"],
      linkerSettings: [
        .unsafeFlags([
          "-framework", "AppKit",
        ])
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
