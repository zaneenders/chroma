import Foundation
import Testing

@testable import ChromaInstaller

private struct Fixture {
  let directory: URL
  let home: URL
  var prefix: URL { home.appendingPathComponent(".local") }
  let bin: URL
  var binary: URL { bin.appendingPathComponent("Demo") }

  init() throws {
    #if os(macOS)
    let temporaryDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
    #else
    let temporaryDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    #endif
    directory = temporaryDirectory.appendingPathComponent("chroma-install-tests-\(UUID().uuidString)")
    home = directory.appendingPathComponent("test home")
    bin = directory.appendingPathComponent("build output")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: directory.appendingPathComponent("Packaging"), withIntermediateDirectories: true)
    try writePlist()
    try "#!/bin/sh\nexit 0\n".write(to: binary, atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    try "license".write(to: directory.appendingPathComponent("LICENSE"), atomically: false, encoding: .utf8)
    try Data([1, 2, 3]).write(to: directory.appendingPathComponent("Packaging/AppIcon.png"))
    for suffix in ["resources", "bundle"] {
      let resources = bin.appendingPathComponent("demo_Font.\(suffix)")
      try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
      try "font".write(to: resources.appendingPathComponent("font"), atomically: false, encoding: .utf8)
    }
  }

  func writePlist(name: String = "Demo App") throws {
    let plist = [
      "CFBundleIdentifier": "com.example.demo", "CFBundleExecutable": "Demo", "CFBundlePackageType": "APPL",
      "CFBundleName": name, "NSDesktopFolderUsageDescription": "Preserve app privacy settings.",
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: directory.appendingPathComponent("Packaging/Info.plist"))
  }

  func installer() throws -> AppInstaller {
    AppInstaller(metadata: try AppMetadata(package: directory, product: "Demo"), home: home)
  }

  #if os(Linux)
  func legacyInstaller() throws -> AppInstaller {
    let fm = FileManager.default
    let packaging = directory.appendingPathComponent("Packaging/Linux")
    try fm.createDirectory(at: packaging, withIntermediateDirectories: true)
    let plist = ["CFBundleName": "Scribe", "CFBundleIdentifier": "com.zaneenders.scribe"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: directory.appendingPathComponent("Packaging/Info.plist"))
    let template = """
      [Desktop Entry]
      Type=Application
      Name=Scribe
      Exec="@SCRIBE_WAYLAND_EXEC@"
      Icon=com.zaneenders.scribe
      Terminal=false

      """
    try template.write(
      to: packaging.appendingPathComponent("com.zaneenders.scribe.desktop"), atomically: false, encoding: .utf8)
    try fm.removeItem(at: directory.appendingPathComponent("Packaging/AppIcon.png"))
    try Data([1, 2, 3]).write(to: packaging.appendingPathComponent("com.zaneenders.scribe.png"))
    let launcher = prefix.appendingPathComponent("bin/scribe-wayland")
    let desktop = prefix.appendingPathComponent("share/applications/com.zaneenders.scribe.desktop")
    for file in [launcher, desktop] {
      try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    try Data([0x7F, 0x45, 0x4C, 0x46, 1, 2, 3, 4]).write(to: launcher)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    try template.replacingOccurrences(of: "@SCRIBE_WAYLAND_EXEC@", with: launcher.path)
      .write(to: desktop, atomically: false, encoding: .utf8)
    try fm.copyItem(at: binary, to: bin.appendingPathComponent("scribe-wayland"))
    return AppInstaller(metadata: try AppMetadata(package: directory, product: "scribe-wayland"), home: home)
  }
  #endif

  #if os(Linux)
  func legacyShapeTreeInstaller() throws -> AppInstaller {
    let fm = FileManager.default
    let plist = ["CFBundleName": "ShapeTree", "CFBundleIdentifier": "shape-tree.ShapeTreeApp"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: directory.appendingPathComponent("Packaging/Info.plist"))
    let app = prefix.appendingPathComponent("lib/shape-tree")
    let launcher = prefix.appendingPathComponent("bin/shape-tree")
    let desktop = prefix.appendingPathComponent("share/applications/shape-tree.ShapeTreeDesktop.desktop")
    for folder in [app, launcher.deletingLastPathComponent(), desktop.deletingLastPathComponent()] {
      try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try Data().write(to: app.appendingPathComponent(".shape-tree-install"))
    try fm.copyItem(at: binary, to: app.appendingPathComponent("ShapeTreeDesktop"))
    try fm.copyItem(at: binary, to: bin.appendingPathComponent("ShapeTreeDesktop"))
    try fm.createSymbolicLink(at: launcher, withDestinationURL: app.appendingPathComponent("ShapeTreeDesktop"))
    try """
    [Desktop Entry]
    Type=Application
    Name=ShapeTree
    Comment=Journal and personal assistant
    Exec="\(launcher.path)"
    Icon=shape-tree.ShapeTreeDesktop
    Terminal=false
    Categories=Office;

    """.write(to: desktop, atomically: false, encoding: .utf8)
    return AppInstaller(metadata: try AppMetadata(package: directory, product: "ShapeTreeDesktop"), home: home)
  }
  #endif

  func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

struct InstallerTests {
  @Test func discoversMetadataWithoutAnInstallerConfiguration() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let metadata = try AppMetadata(package: fixture.directory, product: "Demo")
    #expect(metadata.name == "Demo App")
    #expect(metadata.identifier == "com.example.demo")
    #expect(metadata.license?.lastPathComponent == "LICENSE")
    let plist = try #require(
      PropertyListSerialization.propertyList(from: metadata.infoPlist, format: nil) as? [String: String])
    #expect(plist["NSDesktopFolderUsageDescription"] == "Preserve app privacy settings.")
    #expect(plist["CFBundleExecutable"] == "Demo")
    for product in ["", "../escape", "--flag", ".", "..", "bad\nname"] {
      #expect(throws: InstallError.self) { try AppMetadata(package: fixture.directory, product: product) }
    }
    try fixture.writePlist(name: "../escape")
    #expect(throws: InstallError.self) { try AppMetadata(package: fixture.directory, product: "Demo") }
    try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("Packaging"))
    let defaults = try AppMetadata(package: fixture.directory, product: "Demo")
    #expect(defaults.name == "Demo")
    #expect(defaults.identifier == "local.Demo")
    #expect(defaults.icon == nil)
  }

  @Test func packagingAssetLinksAreCopiedAsFiles() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let fm = FileManager.default
    let license = fixture.directory.appendingPathComponent("LICENSE")
    let original = fixture.directory.appendingPathComponent("root-license")
    try fm.moveItem(at: license, to: original)
    try fm.createSymbolicLink(at: license, withDestinationURL: original)
    let metadata = try AppMetadata(package: fixture.directory, product: "Demo")
    #expect(metadata.license == original.resolvingSymlinksInPath())
  }

  @Test func selectsAStableDevelopmentIdentity() throws {
    let output = """
        1) 012345 "Apple Distribution: Other (TEAM)"
        2) 567890 "Apple Development: Example (TEAM)"
        3) 123456 "Apple Development: Second (TEAM)"
           3 valid identities found
      """
    #expect(try developmentIdentity(in: output) == "Apple Development: Example (TEAM)")
  }

  @Test(arguments: ["", "0 valid identities found", "1) 012345 \"Apple Distribution: Other (TEAM)\""])
  func missingDevelopmentIdentityExplainsKeychainAccess(output: String) throws {
    let error = try #require(throws: InstallError.self) {
      try developmentIdentity(in: output)
    }
    #expect(error.description.contains("--disable-sandbox"))
    #expect(error.description.contains("Xcode"))
  }

  @Test func commandOutputAndFailuresPropagate() throws {
    #expect(try runCommand("/bin/sh", ["-c", "printf identity"], capture: true) == "identity")
    #expect(throws: InstallError.self) { try runCommand("/bin/sh", ["-c", "exit 17"]) }
  }

  #if os(Linux)
  @Test func migratesLegacyShapeTreeWithoutChangingItsLauncher() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.legacyShapeTreeInstaller()
    let fm = FileManager.default
    let old = installer.destination.appendingPathComponent("old")
    try "preserved".write(to: old, atomically: false, encoding: .utf8)
    try installer.install(binary: fixture.bin.appendingPathComponent("ShapeTreeDesktop"))
    #expect(installer.destination == fixture.prefix.appendingPathComponent("lib/shape-tree"))
    #expect(
      try fm.destinationOfSymbolicLink(atPath: fixture.prefix.appendingPathComponent("bin/shape-tree").path)
        == installer.destination.appendingPathComponent("ShapeTreeDesktop").path)
    let backups = try fm.contentsOfDirectory(
      at: fixture.prefix.appendingPathComponent("lib"), includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.hasPrefix(".chroma-install-") }
    let backup = try #require(backups.first)
    #expect(try String(contentsOf: backup.appendingPathComponent("backup-0/old"), encoding: .utf8) == "preserved")
    #expect(!exists(old))
    try installer.install(binary: fixture.bin.appendingPathComponent("ShapeTreeDesktop"))
    #expect(try String(contentsOf: backup.appendingPathComponent("backup-0/old"), encoding: .utf8) == "preserved")
  }

  @Test(arguments: ["marker", "launcher", "desktop"])
  func rejectsUnrecognizedShapeTreeInstall(change: String) throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.legacyShapeTreeInstaller()
    let fm = FileManager.default
    switch change {
    case "marker": try fm.removeItem(at: installer.destination.appendingPathComponent(".shape-tree-install"))
    case "launcher":
      let launcher = fixture.prefix.appendingPathComponent("bin/shape-tree")
      try fm.removeItem(at: launcher)
      try fm.createSymbolicLink(at: launcher, withDestinationURL: fixture.binary)
    default:
      try "unrelated".write(
        to: fixture.prefix.appendingPathComponent("share/applications/shape-tree.ShapeTreeDesktop.desktop"),
        atomically: false, encoding: .utf8)
    }
    #expect(throws: InstallError.self) {
      try installer.install(binary: fixture.bin.appendingPathComponent("ShapeTreeDesktop"))
    }
    #expect(exists(installer.destination.appendingPathComponent("ShapeTreeDesktop")))
  }

  @Test func migratesRecognizedLegacyInstallAndPreservesBackups() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.legacyInstaller()
    let launcher = fixture.prefix.appendingPathComponent("bin/scribe-wayland")
    let desktop = fixture.prefix.appendingPathComponent("share/applications/com.zaneenders.scribe.desktop")
    let oldBinary = try Data(contentsOf: launcher)
    let oldDesktop = try Data(contentsOf: desktop)
    let newBinary = fixture.bin.appendingPathComponent("scribe-wayland")
    try installer.preflight()
    try installer.install(binary: newBinary)
    let fm = FileManager.default
    #expect(
      try fm.destinationOfSymbolicLink(atPath: launcher.path)
        == installer.destination.appendingPathComponent("scribe-wayland").path)
    #expect(try Data(contentsOf: installer.destination.appendingPathComponent("AppIcon.png")) == Data([1, 2, 3]))
    let backups = try fm.contentsOfDirectory(
      at: fixture.prefix.appendingPathComponent("lib"), includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.hasPrefix(".chroma-install-") }
    let backup = try #require(backups.first)
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: backup.appendingPathComponent("backup-0")) == oldBinary)
    #expect(try Data(contentsOf: backup.appendingPathComponent("backup-1")) == oldDesktop)
    try installer.install(binary: newBinary)
    #expect(try Data(contentsOf: backup.appendingPathComponent("backup-0")) == oldBinary)
    #expect(try Data(contentsOf: backup.appendingPathComponent("backup-1")) == oldDesktop)
  }

  @Test(arguments: ["desktop", "script", "symlink", "missing-desktop", "missing-template"])
  func refusesUnrecognizedLegacyInstalls(change: String) throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    _ = try fixture.legacyInstaller()
    let fm = FileManager.default
    let launcher = fixture.prefix.appendingPathComponent("bin/scribe-wayland")
    let desktop = fixture.prefix.appendingPathComponent("share/applications/com.zaneenders.scribe.desktop")
    switch change {
    case "desktop":
      let text = try String(contentsOf: desktop, encoding: .utf8)
      try (text + "Exec=/unrelated\n").write(to: desktop, atomically: false, encoding: .utf8)
    case "script":
      try "#!/bin/sh\nexit 0\n".write(to: launcher, atomically: false, encoding: .utf8)
    case "symlink":
      try fm.removeItem(at: launcher)
      try fm.createSymbolicLink(at: launcher, withDestinationURL: fixture.binary)
    case "missing-desktop": try fm.removeItem(at: desktop)
    default:
      try fm.removeItem(at: fixture.directory.appendingPathComponent("Packaging/Linux/com.zaneenders.scribe.desktop"))
    }
    let before = try Data(contentsOf: launcher)
    let installer = AppInstaller(
      metadata: try AppMetadata(package: fixture.directory, product: "scribe-wayland"), home: fixture.home)
    #expect(throws: InstallError.self) {
      try installer.install(binary: fixture.bin.appendingPathComponent("scribe-wayland"))
    }
    #expect(try Data(contentsOf: launcher) == before)
    #expect(!exists(installer.destination))
  }

  @Test func failedLegacyBuildInputsLeaveOriginalFilesInPlace() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.legacyInstaller()
    let launcher = fixture.prefix.appendingPathComponent("bin/scribe-wayland")
    let desktop = fixture.prefix.appendingPathComponent("share/applications/com.zaneenders.scribe.desktop")
    let oldBinary = try Data(contentsOf: launcher)
    let oldDesktop = try Data(contentsOf: desktop)
    #expect(throws: InstallError.self) {
      try installer.install(binary: fixture.directory.appendingPathComponent("missing"))
    }
    #expect(try Data(contentsOf: launcher) == oldBinary)
    #expect(try Data(contentsOf: desktop) == oldDesktop)
    #expect(!exists(installer.destination))
  }

  @Test func installsExecutableResourcesLicenseIconAndSymlinkThenUpgrades() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.installer()
    try installer.install(binary: fixture.binary)
    let fm = FileManager.default
    let installed = installer.destination.appendingPathComponent("Demo")
    #expect(try Data(contentsOf: installed) == Data(contentsOf: fixture.binary))
    #expect(fm.isExecutableFile(atPath: installed.path))
    for resource in ["demo_Font.resources/font", "demo_Font.bundle/font", "LICENSE", "AppIcon.png"] {
      #expect(fm.fileExists(atPath: installer.destination.appendingPathComponent(resource).path))
    }
    let launcher = fixture.prefix.appendingPathComponent("bin/Demo")
    #expect(try fm.destinationOfSymbolicLink(atPath: launcher.path) == installed.path)
    let desktop = fixture.prefix.appendingPathComponent("share/applications/com.example.demo.desktop")
    let contents = try String(contentsOf: desktop, encoding: .utf8)
    #expect(contents.contains("Exec=\"\(launcher.path)\""))
    #expect(contents.contains("Name=Demo App"))
    try "old".write(to: installer.destination.appendingPathComponent("obsolete"), atomically: false, encoding: .utf8)
    try fixture.writePlist(name: "Renamed App")
    try fixture.installer().install(binary: fixture.binary)
    #expect(!fm.fileExists(atPath: installer.destination.appendingPathComponent("obsolete").path))
    #expect(try String(contentsOf: desktop, encoding: .utf8).contains("Name=Renamed App"))
  }

  @Test func refusesUnrelatedDestinationsAndLeavesPreviousInstallOnInputFailure() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.installer()
    let fm = FileManager.default
    try fm.createDirectory(at: installer.destination, withIntermediateDirectories: true)
    #expect(throws: InstallError.self) { try installer.preflight() }
    try fm.removeItem(at: installer.destination)
    try installer.install(binary: fixture.binary)
    let installed = installer.destination.appendingPathComponent("Demo")
    let original = try Data(contentsOf: installed)
    try fm.removeItem(at: fixture.binary)
    #expect(throws: InstallError.self) { try installer.install(binary: fixture.binary) }
    #expect(try Data(contentsOf: installed) == original)
    let desktop = fixture.prefix.appendingPathComponent("share/applications/com.example.demo.desktop")
    let contents = try String(contentsOf: desktop, encoding: .utf8)
    try (contents + "Exec=/unrelated\n").write(to: desktop, atomically: false, encoding: .utf8)
    #expect(throws: InstallError.self) { try installer.preflight() }
    #expect(try Data(contentsOf: installed) == original)
  }

  @Test func refusesSymlinkedDestinationsAndUnrelatedLaunchers() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.installer()
    let fm = FileManager.default
    try fm.createDirectory(at: fixture.prefix.appendingPathComponent("lib"), withIntermediateDirectories: true)
    let absent = fixture.directory.appendingPathComponent("absent")
    try fm.createSymbolicLink(at: installer.destination, withDestinationURL: absent)
    #expect(throws: InstallError.self) { try installer.preflight() }
    try fm.removeItem(at: installer.destination)
    let launchDirectory = fixture.prefix.appendingPathComponent("bin")
    try fm.createDirectory(at: launchDirectory, withIntermediateDirectories: true)
    let launcher = launchDirectory.appendingPathComponent("Demo")
    for target in [absent, fixture.binary] {
      try fm.createSymbolicLink(at: launcher, withDestinationURL: target)
      #expect(throws: InstallError.self) { try installer.preflight() }
      #expect(try fm.destinationOfSymbolicLink(atPath: launcher.path) == target.path)
      try fm.removeItem(at: launcher)
    }
    try "unrelated".write(to: launcher, atomically: false, encoding: .utf8)
    #expect(throws: InstallError.self) { try installer.preflight() }
    #expect(try String(contentsOf: launcher, encoding: .utf8) == "unrelated")
    try fm.removeItem(at: launchDirectory)
    try fm.createSymbolicLink(at: launchDirectory, withDestinationURL: fixture.bin)
    #expect(throws: InstallError.self) { try installer.preflight() }
  }

  @Test func refusesSymlinkedOwnershipAndMissingAssets() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.installer()
    try installer.install(binary: fixture.binary)
    let fm = FileManager.default
    let ownership = installer.destination.appendingPathComponent(".chroma-install")
    let backup = fixture.directory.appendingPathComponent("marker")
    try fm.moveItem(at: ownership, to: backup)
    try fm.createSymbolicLink(at: ownership, withDestinationURL: backup)
    #expect(throws: InstallError.self) { try installer.preflight() }
    try fm.removeItem(at: ownership)
    try fm.moveItem(at: backup, to: ownership)
    let resource = fixture.bin.appendingPathComponent("demo_Font.resources")
    let movedResource = fixture.directory.appendingPathComponent("external.resources")
    try fm.moveItem(at: resource, to: movedResource)
    try fm.createSymbolicLink(at: resource, withDestinationURL: movedResource)
    #expect(throws: InstallError.self) { try installer.install(binary: fixture.binary) }
    #expect(FileManager.default.isExecutableFile(atPath: installer.destination.appendingPathComponent("Demo").path))
    try fm.removeItem(at: fixture.directory.appendingPathComponent("Packaging/AppIcon.png"))
    #expect(throws: InstallError.self) { try installer.preflight() }
  }
  #else
  @Test func explicitMacDirectoryUpdatesOnlyTheSelectedInstallation() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let metadata = try AppMetadata(package: fixture.directory, product: "Demo")
    let directory = fixture.directory.appendingPathComponent("system Applications")
    let installer = AppInstaller(metadata: metadata, home: fixture.home, installDirectory: directory)
    #expect(installer.destination == directory.appendingPathComponent("Demo App.app"))
    try installer.preflight()
    let resources = installer.destination.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try Data("chroma-install-v1:com.example.demo\n".utf8).write(to: resources.appendingPathComponent(".chroma-install"))
    try installer.preflight()
    #expect(!exists(fixture.home.appendingPathComponent("Applications/Demo App.app")))
  }

  @Test func explicitMacDirectoryStillRejectsUnrelatedAppsAndSymlinks() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let fm = FileManager.default
    let directory = fixture.directory.appendingPathComponent("system Applications")
    let installer = AppInstaller(
      metadata: try AppMetadata(package: fixture.directory, product: "Demo"),
      home: fixture.home, installDirectory: directory)
    try fm.createDirectory(at: installer.destination, withIntermediateDirectories: true)
    #expect(throws: InstallError.self) { try installer.preflight() }
    try fm.removeItem(at: installer.destination)
    try fm.createSymbolicLink(at: installer.destination, withDestinationURL: fixture.bin)
    #expect(throws: InstallError.self) { try installer.preflight() }
    try fm.removeItem(at: installer.destination)
    try fm.removeItem(at: directory)
    try fm.createSymbolicLink(at: directory, withDestinationURL: fixture.bin)
    #expect(throws: InstallError.self) { try installer.preflight() }
  }

  @Test func macProcessDetectionMatchesExecutableNamesNotShellArguments() {
    #expect(macAppIsRunning(in: "launchd\n  ShapeTreeDesktop\nsh\n", product: "ShapeTreeDesktop"))
    for names in ["ShapeTreeDesktopOther\n", "sh\nDemo\n", ""] {
      #expect(!macAppIsRunning(in: names, product: "ShapeTreeDesktop"))
    }
  }

  @Test func macDestinationUsesBundleName() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let installer = try fixture.installer()
    #expect(installer.destination == fixture.home.appendingPathComponent("Applications/Demo App.app"))
    try installer.preflight()
  }
  #endif

  @Test func rollsBackAllFilesAfterAMoveFailure() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let fm = FileManager.default
    let staging = fixture.directory.appendingPathComponent("staging")
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    let first = fixture.directory.appendingPathComponent("first")
    let second = fixture.directory.appendingPathComponent("second")
    let newFirst = staging.appendingPathComponent("new-first")
    let newSecond = staging.appendingPathComponent("new-second")
    for (file, contents) in [
      (first, "old-first"), (second, "old-second"), (newFirst, "new-first"), (newSecond, "new-second"),
    ] {
      try contents.write(to: file, atomically: false, encoding: .utf8)
    }
    #expect(throws: InstallError.self) {
      try replaceInstalledFiles([(newFirst, first), (newSecond, second)], staging: staging) { source, target in
        if source == newSecond { throw InstallError("Injected move failure") }
        try fm.moveItem(at: source, to: target)
      }
    }
    #expect(try String(contentsOf: first, encoding: .utf8) == "old-first")
    #expect(try String(contentsOf: second, encoding: .utf8) == "old-second")
  }

  @Test func reportsPreservedBackupsIfRollbackFails() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let fm = FileManager.default
    let staging = fixture.directory.appendingPathComponent("staging")
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    let destination = fixture.directory.appendingPathComponent("previous")
    let source = staging.appendingPathComponent("new")
    try "original".write(to: destination, atomically: false, encoding: .utf8)
    try "replacement".write(to: source, atomically: false, encoding: .utf8)
    #expect(throws: RollbackFailure.self) {
      try replaceInstalledFiles([(source, destination)], staging: staging) { from, to in
        if from == source || from.lastPathComponent == "backup-0" { throw InstallError("Injected failure") }
        try fm.moveItem(at: from, to: to)
      }
    }
    #expect(try String(contentsOf: staging.appendingPathComponent("backup-0"), encoding: .utf8) == "original")
  }
}
