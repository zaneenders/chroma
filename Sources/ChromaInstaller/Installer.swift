import Foundation

struct Installer {
  let config: Configuration
  let destination: URL
  let prefix: URL
  private let fm = FileManager.default
  private var markerPath: String {
    #if os(Linux)
    ".chroma-install"
    #else
    "Contents/Resources/.chroma-install"
    #endif
  }
  private var marker: String { "chroma-install-v1:\(config.identifier)" }

  init(config: Configuration, base: URL) throws {
    self.config = config
    #if os(Linux)
    prefix = resolve(config.linuxPrefix, relativeTo: base)
    destination = prefix.appendingPathComponent("lib/\(config.identifier)")
    // Conservative quoting policy for generated desktop entries; spaces are supported.
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._- ")
    guard prefix.path.unicodeScalars.allSatisfy(safe.contains) else {
      throw InstallError("Linux prefix supports letters, digits, spaces, /, ., _, and - only.")
    }
    #else
    destination = resolve(config.macOSDestination, relativeTo: base)
    prefix = destination.deletingLastPathComponent()
    guard destination.pathExtension == "app" else { throw InstallError("Destination must end in .app.") }
    #endif
  }

  private var launcher: URL { prefix.appendingPathComponent("bin/\(config.product)") }
  private var desktop: URL { prefix.appendingPathComponent("share/applications/\(config.identifier).desktop") }

  func preflight() throws {
    try rejectSymlinks(destination)
    if fm.fileExists(atPath: destination.path) {
      let ownership = destination.appendingPathComponent(markerPath)
      guard (try? String(contentsOf: ownership, encoding: .utf8)) == marker else {
        throw InstallError("Refusing to replace unrelated installation: \(destination.path)")
      }
    }
    #if os(Linux)
    for file in [launcher, desktop] {
      try rejectSymlinks(file)
      if fm.fileExists(atPath: file.path) {
        let contents = try String(contentsOf: file, encoding: .utf8)
        guard contents.components(separatedBy: "\n").contains("# \(marker)") else {
          throw InstallError("Refusing to replace unrelated file: \(file.path)")
        }
      }
    }
    #endif
  }

  func install(from bin: URL) async throws {
    try preflight()
    let executable = bin.appendingPathComponent(config.product)
    guard fm.isExecutableFile(atPath: executable.path) else {
      throw InstallError("Missing executable: \(executable.path)")
    }
    let parent = destination.deletingLastPathComponent()
    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
    let staging = parent.appendingPathComponent(".chroma-install-\(UUID().uuidString)")
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    var preserveStaging = false
    defer { if !preserveStaging { try? fm.removeItem(at: staging) } }
    let app = staging.appendingPathComponent("app")
    #if os(Linux)
    let executableDirectory = app
    let resources = app
    let resourceExtension = "resources"
    #else
    let executableDirectory = app.appendingPathComponent("Contents/MacOS")
    let resources = app.appendingPathComponent("Contents/Resources")
    let resourceExtension = "bundle"
    #endif
    try fm.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
    try fm.copyItem(at: executable, to: executableDirectory.appendingPathComponent(config.product))
    for entry in try fm.contentsOfDirectory(at: bin, includingPropertiesForKeys: [.isDirectoryKey])
    where entry.pathExtension == resourceExtension {
      guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
      try fm.copyItem(at: entry, to: resources.appendingPathComponent(entry.lastPathComponent))
    }
    try marker.write(to: app.appendingPathComponent(markerPath), atomically: true, encoding: .utf8)
    var replacements: [(URL, URL)] = [(app, destination)]
    #if os(Linux)
    let stagedLauncher = staging.appendingPathComponent("launcher")
    try """
    #!/bin/sh
    # \(marker)
    exec "\(destination.path)/\(config.product)" "$@"

    """.write(to: stagedLauncher, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedLauncher.path)
    let stagedDesktop = staging.appendingPathComponent("desktop")
    let name = config.displayName.replacingOccurrences(of: "\\", with: "\\\\")
    try """
    [Desktop Entry]
    # \(marker)
    Type=Application
    Name=\(name)
    Exec="\(launcher.path)"
    Terminal=false
    Categories=Development;

    """.write(to: stagedDesktop, atomically: true, encoding: .utf8)
    replacements += [(stagedLauncher, launcher), (stagedDesktop, desktop)]
    #else
    let plist: [String: Any] = [
      "CFBundleIdentifier": config.identifier,
      "CFBundleName": config.displayName,
      "CFBundleExecutable": config.product,
      "CFBundlePackageType": "APPL",
      "CFBundleVersion": "1",
      "CFBundleShortVersionString": "1.0",
      "NSHighResolutionCapable": true,
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: app.appendingPathComponent("Contents/Info.plist"))
    try await command("/usr/bin/codesign", ["--force", "--sign", config.signingIdentity, app.path])
    try await command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    #endif
    try preflight()
    // Back up every managed destination before replacing it. Roll back all completed steps on failure.
    var backups: [(URL, URL)] = []
    var installed: [URL] = []
    do {
      for (source, target) in replacements {
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) {
          let backup = staging.appendingPathComponent("backup-\(backups.count)")
          try fm.moveItem(at: target, to: backup)
          backups.append((backup, target))
        }
        try fm.moveItem(at: source, to: target)
        installed.append(target)
      }
    } catch {
      let original = error
      do {
        for target in installed.reversed() { try fm.removeItem(at: target) }
        for (backup, target) in backups.reversed() { try fm.moveItem(at: backup, to: target) }
      } catch {
        preserveStaging = true
        throw InstallError(
          "Installation failed: \(original). Rollback failed: \(error). Backups preserved at \(staging.path)")
      }
      throw original
    }
  }
}

// Reject symlinked destinations and ancestors, including dangling links.
func rejectSymlinks(_ url: URL) throws {
  var current = url
  while current.path != "/" {
    if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
      throw InstallError("Refusing symlinked installation path: \(current.path)")
    }
    current.deleteLastPathComponent()
  }
}
