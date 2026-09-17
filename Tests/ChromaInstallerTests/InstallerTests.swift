import Foundation
import Testing

@testable import ChromaInstaller

struct InstallerTests {
  func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("chroma-installer-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func configRoundTripAndRelativePaths() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = Configuration(product: "Demo", displayName: "Demo App", identifier: "local.Demo")
    let file = directory.appendingPathComponent("config.json")
    try config.save(file)
    #expect(try Configuration.load(file) == config)
    #expect(resolve("App", relativeTo: directory).path == directory.appendingPathComponent("App").path)
  }

  @Test func invalidConfigurationAndArguments() throws {
    var config = Configuration(product: "../Demo", displayName: "Demo", identifier: "local.Demo")
    #expect(throws: InstallError.self) { try config.validate() }
    config.product = "Demo"
    config.identifier = ".."
    #expect(throws: InstallError.self) { try config.validate() }
    config.identifier = "local.Demo"
    config.version = 2
    #expect(throws: InstallError.self) { try config.validate() }
    #expect(throws: InstallError.self) { try Options(["--prefix"]) }
    #expect(throws: InstallError.self) { try Options(["a.json", "b.json"]) }
    #expect(throws: InstallError.self) { try Options(["--unknown"]) }
    let options = try Options(["a.json", "--yes", "--prefix", "/tmp/My Apps"])
    #expect(options.yes && options.config == "a.json")
    #expect(options.overrides["--prefix"] == "/tmp/My Apps")
  }

  #if os(Linux)
  @Test func installReinstallAndResourceCopy() async throws {
    let fm = FileManager.default
    let directory = try temporaryDirectory()
    defer { try? fm.removeItem(at: directory) }
    let bin = directory.appendingPathComponent("build")
    let bundle = bin.appendingPathComponent("chroma_ChromaFont.resources")
    try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
    try "license".write(to: bundle.appendingPathComponent("OFL.txt"), atomically: true, encoding: .utf8)
    let executable = bin.appendingPathComponent("Demo")
    try "#!/bin/sh\necho demo\n".write(to: executable, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    var config = Configuration(product: "Demo", displayName: "Demo", identifier: "local.Demo")
    config.linuxPrefix = directory.appendingPathComponent("My Apps").path
    let installer = try Installer(config: config, base: directory)
    try await installer.install(from: bin)
    try await installer.install(from: bin)
    #expect(
      fm.fileExists(atPath: installer.destination.appendingPathComponent("chroma_ChromaFont.resources/OFL.txt").path))
    #expect(try await capture(directory.appendingPathComponent("My Apps/bin/Demo").path, []) == "demo\n")
    let desktop = try String(
      contentsOf: directory.appendingPathComponent("My Apps/share/applications/local.Demo.desktop"), encoding: .utf8)
    #expect(desktop.contains("Exec=\"\(directory.path)/My Apps/bin/Demo\""))
    #expect(try fm.contentsOfDirectory(atPath: directory.appendingPathComponent("My Apps/lib").path) == ["local.Demo"])
  }

  @Test func rollsBackWhenLauncherCannotBeInstalled() async throws {
    let fm = FileManager.default
    let directory = try temporaryDirectory()
    defer { try? fm.removeItem(at: directory) }
    let bin = directory.appendingPathComponent("build")
    try fm.createDirectory(at: bin, withIntermediateDirectories: true)
    let executable = bin.appendingPathComponent("Demo")
    try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    var config = Configuration(product: "Demo", displayName: "Demo", identifier: "local.Demo")
    config.linuxPrefix = directory.appendingPathComponent("prefix").path
    let installer = try Installer(config: config, base: directory)
    try await installer.install(from: bin)
    let original = installer.destination.appendingPathComponent("original")
    try "preserved".write(to: original, atomically: true, encoding: .utf8)
    let launcherDirectory = directory.appendingPathComponent("prefix/bin")
    try fm.removeItem(at: launcherDirectory)
    try "blocking file".write(to: launcherDirectory, atomically: true, encoding: .utf8)
    await #expect(throws: (any Error).self) { try await installer.install(from: bin) }
    #expect(try String(contentsOf: original, encoding: .utf8) == "preserved")
  }

  @Test func refusesUnrelatedFilesAndSymlinks() throws {
    let fm = FileManager.default
    let directory = try temporaryDirectory()
    defer { try? fm.removeItem(at: directory) }
    var config = Configuration(product: "Demo", displayName: "Demo", identifier: "local.Demo")
    config.linuxPrefix = directory.path
    let installer = try Installer(config: config, base: directory)
    try fm.createDirectory(at: installer.destination, withIntermediateDirectories: true)
    #expect(throws: InstallError.self) { try installer.preflight() }
    try fm.removeItem(at: installer.destination)
    try fm.createSymbolicLink(
      at: installer.destination, withDestinationURL: directory.appendingPathComponent("missing"))
    #expect(throws: InstallError.self) { try installer.preflight() }
    try fm.removeItem(at: installer.destination)
    let launcher = directory.appendingPathComponent("bin/Demo")
    try fm.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "unrelated".write(to: launcher, atomically: true, encoding: .utf8)
    #expect(throws: InstallError.self) { try installer.preflight() }
    #expect(try String(contentsOf: launcher, encoding: .utf8) == "unrelated")
  }
  #endif
}
