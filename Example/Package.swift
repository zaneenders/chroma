// swift-tools-version: 6.4
import PackageDescription

var dependencies: [Target.Dependency] = [
  "DemoContent",
  .product(name: "Chroma", package: "chroma"),
]
var targets: [Target] = [
  .target(
    name: "DemoBackend",
    dependencies: [
      "DemoContent", .product(name: "Chroma", package: "chroma"),
      .product(name: "RemoteServer", package: "chroma"),
    ]),
  .testTarget(
    name: "DemoContentTests",
    dependencies: [
      "DemoContent", .product(name: "HeadlessBackend", package: "chroma"),
      .product(name: "RemoteProtocol", package: "chroma"),
    ]
  ),
  .target(
    name: "DemoContent",
    dependencies: [
      "DemoImages", .product(name: "Chroma", package: "chroma"),
      .product(name: "RemoteProtocol", package: "chroma"),
    ]
  ),
  .target(
    name: "DemoImages",
    dependencies: [.product(name: "Chroma", package: "chroma")]
  ),
  .executableTarget(
    name: "RemoteDemoDaemon",
    dependencies: [
      "DemoContent", "DemoBackend",
      .product(name: "Chroma", package: "chroma"),
      .product(name: "RemoteServer", package: "chroma"),
      .product(name: "RemoteProtocol", package: "chroma"),
      .product(name: "HeadlessBackend", package: "chroma"),
    ]
  ),
]

#if os(macOS)
dependencies.append("DemoBackend")
dependencies.append(.product(name: "RemoteMetalClient", package: "chroma"))
targets.append(
  .executableTarget(
    name: "RemoteDemoClient",
    dependencies: [
      .product(name: "Chroma", package: "chroma"),
      .product(name: "RemoteMetalClient", package: "chroma"),
    ]
  )
)
#elseif os(Linux)
dependencies.append(.product(name: "WaylandBackend", package: "chroma"))
#endif

targets.append(
  .executableTarget(
    name: "ChromaDemo",
    dependencies: dependencies
  )
)

let package = Package(
  name: "ChromaExample",
  platforms: [.macOS(.v27)],
  dependencies: [
    .package(path: "..")
  ],
  targets: targets
)
