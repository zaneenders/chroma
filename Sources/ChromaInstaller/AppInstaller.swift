import Foundation

struct AppInstaller {
  let metadata: AppMetadata
  let profiling: Bool
  let destination: URL
  let prefix: URL
  private let fm = FileManager.default
  private var product: String { metadata.product }
  private var marker: Data { Data("chroma-install-v1:\(metadata.identifier)\n".utf8) }
  private var markerPath: String {
    #if os(Linux)
    ".chroma-install"
    #else
    "Contents/Resources/.chroma-install"
    #endif
  }

  init(
    metadata: AppMetadata, profiling: Bool = true, home: URL = installHome(), installDirectory: URL? = nil
  ) {
    self.metadata = metadata
    self.profiling = profiling
    #if os(Linux)
    prefix = installDirectory ?? home.appendingPathComponent(".local")
    destination = prefix.appendingPathComponent(
      "lib/\(metadata.isShapeTreeDesktop ? "shape-tree" : metadata.identifier)")
    #else
    prefix = installDirectory ?? home.appendingPathComponent("Applications")
    destination = prefix.appendingPathComponent("\(metadata.name).app")
    #endif
  }

  private var launcher: URL {
    prefix.appendingPathComponent("bin/\(metadata.isShapeTreeDesktop ? "shape-tree" : product)")
  }
  private var desktop: URL {
    prefix.appendingPathComponent(
      "share/applications/\(metadata.isShapeTreeDesktop ? "shape-tree.ShapeTreeDesktop" : metadata.identifier).desktop")
  }

  func preflight() throws {
    try rejectSymlinks(destination)
    #if os(Linux)
    let legacy = try isLegacyLinuxInstallation()
    #else
    try requireStoppedMacApp()
    var parent = prefix
    while !exists(parent) { parent.deleteLastPathComponent() }
    guard isDirectory(parent), fm.isWritableFile(atPath: parent.path) else {
      throw InstallError(
        "Cannot write to \(prefix.path). Choose a writable --install-directory; do not run builds with sudo.")
    }
    let legacy = false
    #endif
    if exists(destination), !legacy {
      let ownership = destination.appendingPathComponent(markerPath)
      try rejectSymlinks(ownership)
      guard isDirectory(destination), (try? Data(contentsOf: ownership)) == marker else {
        throw InstallError("Refusing to replace an unrelated installation: \(destination.path)")
      }
    }
    for asset in [metadata.license, metadata.icon].compactMap({ $0 }) { try requireFile(asset) }
    #if os(Linux)
    try rejectSymlinks(launcher.deletingLastPathComponent())
    try rejectSymlinks(desktop)
    if exists(launcher), !legacy {
      guard
        (try? fm.destinationOfSymbolicLink(atPath: launcher.path)) == destination.appendingPathComponent(product).path
      else { throw InstallError("Refusing to replace an unrelated launcher: \(launcher.path)") }
    }
    if exists(desktop), !legacy {
      let saved = destination.appendingPathComponent(".chroma-desktop")
      try rejectSymlinks(saved)
      guard exists(destination), let previous = try? Data(contentsOf: saved),
        (try? Data(contentsOf: desktop)) == previous
      else { throw InstallError("Refusing to replace an unrelated desktop entry: \(desktop.path)") }
    }
    #endif
  }

  func install(binary: URL) throws {
    try preflight()
    try requireFile(binary)
    guard binary.lastPathComponent == product, fm.isExecutableFile(atPath: binary.path) else {
      throw InstallError("Missing executable product \(product): \(binary.path)")
    }
    let parent = destination.deletingLastPathComponent()
    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
    let staging = parent.appendingPathComponent(".chroma-install-\(UUID().uuidString)")
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    var preserveStaging = false
    defer { if !preserveStaging { try? fm.removeItem(at: staging) } }
    #if os(Linux)
    let app = staging.appendingPathComponent("app")
    let executableDirectory = app
    let resources = app
    #else
    let app = staging.appendingPathComponent(destination.lastPathComponent)
    let executableDirectory = app.appendingPathComponent("Contents/MacOS")
    let resources = app.appendingPathComponent("Contents/Resources")
    #endif
    try fm.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
    let installedBinary = executableDirectory.appendingPathComponent(product)
    try fm.copyItem(at: binary, to: installedBinary)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedBinary.path)
    for bundle in try fm.contentsOfDirectory(
      at: binary.deletingLastPathComponent(), includingPropertiesForKeys: [.isDirectoryKey])
    where ["resources", "bundle"].contains(bundle.pathExtension) {
      guard (try? fm.destinationOfSymbolicLink(atPath: bundle.path)) == nil, isDirectory(bundle) else {
        throw InstallError("Resource bundles must be directories, not symlinks: \(bundle.path)")
      }
      try fm.copyItem(at: bundle, to: resources.appendingPathComponent(bundle.lastPathComponent))
    }
    if let license = metadata.license {
      try fm.copyItem(at: license, to: resources.appendingPathComponent("LICENSE"))
    }
    if let icon = metadata.icon {
      try fm.copyItem(at: icon, to: resources.appendingPathComponent("AppIcon.\(icon.pathExtension)"))
    }
    try marker.write(to: app.appendingPathComponent(markerPath))
    var replacements: [(source: URL, destination: URL)] = [(app, destination)]
    #if os(Linux)
    let stagedLauncher = staging.appendingPathComponent("launcher")
    try fm.createSymbolicLink(
      atPath: stagedLauncher.path, withDestinationPath: destination.appendingPathComponent(product).path)
    let stagedDesktop = staging.appendingPathComponent("desktop")
    try desktopEntry.write(to: stagedDesktop, atomically: false, encoding: .utf8)
    try fm.copyItem(at: stagedDesktop, to: app.appendingPathComponent(".chroma-desktop"))
    replacements += [(stagedLauncher, launcher), (stagedDesktop, desktop)]
    #else
    try metadata.infoPlist.write(to: app.appendingPathComponent("Contents/Info.plist"))
    if profiling {
      try runCommand(
        "/usr/bin/dsymutil", [binary.path, "-o", resources.appendingPathComponent("\(product).dSYM").path])
    } else {
      try runCommand("/usr/bin/strip", ["-S", installedBinary.path])
    }
    let identity = try developmentIdentity(
      in: runCommand("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"], capture: true))
    try runCommand("/usr/bin/codesign", ["--force", "--sign", identity, app.path])
    try runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    #endif
    try preflight()
    #if os(Linux)
    let migrating = try isLegacyLinuxInstallation()
    #endif
    do {
      try replaceInstalledFiles(replacements, staging: staging)
    } catch let error as RollbackFailure {
      preserveStaging = true
      throw error
    }
    #if os(Linux)
    if migrating {
      preserveStaging = true
      print("Previous installation files backed up to \(staging.path)")
    }
    #endif
  }

  #if os(macOS)
  private func requireStoppedMacApp() throws {
    let output = try runCommand("/bin/ps", ["-ww", "-axo", "ucomm="], capture: true)
    guard !macAppIsRunning(in: output, product: product) else {
      throw InstallError("Quit \(metadata.name) completely before installing, then rerun this command.")
    }
  }
  #endif

  #if os(Linux)
  private func isLegacyLinuxInstallation() throws -> Bool {
    try rejectSymlinks(launcher.deletingLastPathComponent())
    try rejectSymlinks(desktop)
    if metadata.isShapeTreeDesktop {
      let ownership = destination.appendingPathComponent(".shape-tree-install")
      let executable = destination.appendingPathComponent(product)
      try rejectSymlinks(ownership)
      try rejectSymlinks(executable)
      guard isDirectory(destination), !exists(destination.appendingPathComponent(markerPath)),
        (try? ownership.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
        (try? Data(contentsOf: ownership)) == Data(), fm.isExecutableFile(atPath: executable.path),
        (try? fm.destinationOfSymbolicLink(atPath: launcher.path)) == executable.path
      else { return false }
      let expected = """
        [Desktop Entry]
        Type=Application
        Name=ShapeTree
        Comment=Journal and personal assistant
        Exec="\(launcher.path)"
        Icon=shape-tree.ShapeTreeDesktop
        Terminal=false
        Categories=Office;

        """
      return (try? String(contentsOf: desktop, encoding: .utf8)) == expected
    }
    // The old Scribe packager installed a regular ELF plus this exact desktop template.
    // Do not infer ownership from a filename or an arbitrary Exec line alone.
    guard !exists(destination), let template = metadata.linuxDesktopTemplate,
      template.components(separatedBy: "@SCRIBE_WAYLAND_EXEC@").count == 2,
      template.split(separator: "\n").contains("Exec=\"@SCRIBE_WAYLAND_EXEC@\""),
      metadata.identifier == "com.zaneenders.scribe", product == "scribe-wayland",
      (try? fm.destinationOfSymbolicLink(atPath: launcher.path)) == nil,
      (try? launcher.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
      (try? desktop.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
      fm.isExecutableFile(atPath: launcher.path),
      (try? String(contentsOf: desktop, encoding: .utf8))
        == template.replacingOccurrences(of: "@SCRIBE_WAYLAND_EXEC@", with: launcher.path)
    else { return false }
    let handle = try FileHandle(forReadingFrom: launcher)
    defer { try? handle.close() }
    return try handle.read(upToCount: 4) == Data([0x7F, 0x45, 0x4C, 0x46])
  }
  #endif

  private var desktopEntry: String {
    let escaped = launcher.path.replacingOccurrences(of: "%", with: "%%")
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "`", with: "\\`")
      .replacingOccurrences(of: "$", with: "\\$")
    return """
      [Desktop Entry]
      Type=Application
      Name=\(desktopValue(metadata.name))
      Exec=\(desktopValue("\"\(escaped)\""))
      \(metadata.icon == nil ? "" : "Icon=\(desktopValue(destination.appendingPathComponent("AppIcon.png").path))")
      Terminal=false
      Categories=Utility;

      """
  }
}

private func desktopValue(_ value: String) -> String {
  value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
    .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t")
}

func installHome() -> URL {
  if let home = ProcessInfo.processInfo.environment["HOME"], home.hasPrefix("/") {
    return URL(fileURLWithPath: home, isDirectory: true).resolvingSymlinksInPath()
  }
  return FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
}

func exists(_ url: URL) -> Bool {
  FileManager.default.fileExists(atPath: url.path)
    || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
}

private func isDirectory(_ url: URL) -> Bool {
  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
}

private func requireFile(_ url: URL) throws {
  guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
    throw InstallError("Missing regular file: \(url.path)")
  }
}

func rejectSymlinks(_ url: URL) throws {
  var current = url
  while current.path != "/" {
    if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
      throw InstallError("Refusing symlinked installation path: \(current.path)")
    }
    current.deleteLastPathComponent()
  }
}

#if os(macOS)
func macAppIsRunning(in processNames: String, product: String) -> Bool {
  processNames.split(separator: "\n").contains {
    $0.trimmingCharacters(in: .whitespaces) == product
  }
}
#endif
