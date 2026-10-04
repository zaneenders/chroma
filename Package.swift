// swift-tools-version: 6.4
import PackageDescription

var products: [Product] = [
  .library(name: "Chroma", targets: ["Chroma"]),
  .library(name: "ChromaMarkdown", targets: ["ChromaMarkdown"]),
  .library(name: "ChromaApp", targets: ["ChromaApp"]),
  .library(name: "ChromaFont", targets: ["ChromaFont"]),
  .library(name: "ChromaTesting", targets: ["ChromaTesting"]),
  .library(name: "ChromaHeadless", targets: ["ChromaHeadless"]),
]

var appDependencies: [Target.Dependency] = ["Chroma", "ChromaHeadless"]

var targets: [Target] = [
  .target(
    name: "ChromaMarkdown",
    dependencies: ["Chroma", .product(name: "Markdown", package: "swift-markdown")],
    swiftSettings: [.strictMemorySafety()]),
  .testTarget(name: "ChromaMarkdownTests", dependencies: ["ChromaMarkdown", "ChromaTesting"]),
  .testTarget(
    name: "ChromaTests",
    dependencies: ["Chroma", "ChromaFont", "ChromaTesting"]
  ),
  .target(
    name: "Chroma",
    dependencies: [
      "ChromaFont",
      .product(name: "BasicContainers", package: "swift-collections"),
      .product(name: "ContainersPreview", package: "swift-collections"),
    ],
    swiftSettings: [.strictMemorySafety()]),
  .target(
    name: "ChromaFont", exclude: ["README.md"], resources: [.copy("Resources")],
    swiftSettings: [.strictMemorySafety()]),
  .target(name: "ChromaTesting", dependencies: ["Chroma"]),
  .target(name: "ChromaHeadless", dependencies: ["Chroma", "ChromaTesting"]),
  .testTarget(name: "ChromaHeadlessTests", dependencies: ["ChromaHeadless", "Chroma", "ChromaFont"]),
]
#if os(macOS)
appDependencies.append("MetalBackend")
products.append(.library(name: "MetalBackend", targets: ["MetalBackend"]))
targets.append(contentsOf: [
  .testTarget(name: "MetalBackendTests", dependencies: ["MetalBackend"]),
  .target(
    name: "MetalBackend",
    dependencies: ["Chroma", "ChromaFont"],
    exclude: ["Shaders"],
    swiftSettings: [.strictMemorySafety()],
    plugins: [.plugin(name: "ShaderSourcePlugin")]
  ),
])
#endif

#if os(Linux)
appDependencies.append("WaylandBackend")
products.append(.library(name: "WaylandBackend", targets: ["WaylandBackend"]))
targets.append(contentsOf: [
  .testTarget(
    name: "WaylandBackendTests",
    dependencies: ["WaylandBackend"],
    swiftSettings: [.strictMemorySafety()]
  ),
  .target(
    name: "WaylandBackend",
    dependencies: [
      "Chroma",
      "ChromaFont",
      "CWaylandClient",
      "CWaylandCursor",
      "CWaylandEGL",
      "CWaylandProtocols",
      "CEGL",
      "CGLES3",
      "CXKBKeyboard",
    ],
    exclude: ["Shaders"],
    swiftSettings: [.strictMemorySafety()],
    plugins: [.plugin(name: "ShaderSourcePlugin")]
  ),
  .systemLibrary(
    name: "CWaylandClient",
    path: "Sources/LinkedLibraries/CWaylandClient",
    pkgConfig: "wayland-client"
  ),
  .systemLibrary(
    name: "CWaylandCursor",
    path: "Sources/LinkedLibraries/CWaylandCursor",
    pkgConfig: "wayland-cursor"
  ),
  .systemLibrary(
    name: "CWaylandEGL",
    path: "Sources/LinkedLibraries/CWaylandEGL",
    pkgConfig: "wayland-egl"
  ),
  .systemLibrary(
    name: "CEGL",
    path: "Sources/LinkedLibraries/CEGL",
    pkgConfig: "egl"
  ),
  .systemLibrary(
    name: "CGLES3",
    path: "Sources/LinkedLibraries/CGLES3",
    pkgConfig: "glesv2"
  ),
  .target(
    name: "CWaylandProtocols",
    dependencies: ["CWaylandClient"],
    path: "Sources/LinkedLibraries/CWaylandProtocols",
    publicHeadersPath: "include"
  ),
  .target(
    name: "CXKBKeyboard",
    path: "Sources/LinkedLibraries/CXKBKeyboard",
    publicHeadersPath: "include",
    linkerSettings: [.linkedLibrary("xkbcommon")]
  ),
])
#endif

targets.append(
  .target(name: "ChromaApp", dependencies: appDependencies, swiftSettings: [.strictMemorySafety()])
)

#if os(macOS) || os(Linux)
targets.append(contentsOf: [
  .executableTarget(name: "ShaderSourceGenerator"),
  .plugin(
    name: "ShaderSourcePlugin",
    capability: .buildTool(),
    dependencies: ["ShaderSourceGenerator"]
  ),
])
#endif

for target in targets where target.type != .plugin && target.type != .system {
  if ["CWaylandProtocols", "CXKBKeyboard"].contains(target.name) {
    target.cSettings = (target.cSettings ?? []) + [.treatAllWarnings(as: .error)]
  } else {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
  }
}

let package = Package(
  name: "chroma",
  platforms: [.macOS(.v27)],
  products: products,
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    .package(
      url: "https://github.com/apple/swift-collections.git", exact: "1.7.1",
      traits: ["UnstableContainersPreview"]),
  ],
  targets: targets
)
