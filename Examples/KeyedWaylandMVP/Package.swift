// swift-tools-version: 6.4
import Foundation
import PackageDescription

let native = ProcessInfo.processInfo.environment["MVP_NATIVE"] == "1"
var targets: [Target] = [
    .target(name: "KeyedUI", dependencies: [.product(name: "FrameArena", package: "FrameArena")], swiftSettings: [.enableExperimentalFeature("Lifetimes")]),
    .executableTarget(name: "KeyedDemo", dependencies: ["KeyedUI"] + (native ? ["WaylandBridge"] : []), swiftSettings: [.enableExperimentalFeature("Lifetimes")] + (native ? [.define("MVP_NATIVE")] : [])),
    .testTarget(name: "KeyedUITests", dependencies: ["KeyedUI"], swiftSettings: [.enableExperimentalFeature("Lifetimes")]),
]
// The native bridge is opt-in, so the ownership/core tests need no display libraries.
if native {
    targets.append(.target(name: "WaylandBridge", path: "Sources/WaylandBridge", publicHeadersPath: "include", cSettings: [.define("WB_NATIVE")], linkerSettings: [.linkedLibrary("wayland-client"), .linkedLibrary("wayland-egl"), .linkedLibrary("EGL"), .linkedLibrary("GLESv2"), .linkedLibrary("m"), .linkedLibrary("m")]))
}
let package = Package(name: "KeyedWaylandMVP", platforms: [.macOS("27.0")], products: [.library(name: "KeyedUI", targets: ["KeyedUI"]), .executable(name: "keyed-demo", targets: ["KeyedDemo"])], dependencies: [.package(path: "Vendor/FrameArena")], targets: targets)
