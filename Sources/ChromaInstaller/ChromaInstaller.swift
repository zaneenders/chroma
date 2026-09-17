import Foundation
import Subprocess

#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct ChromaInstaller {
  static func main() async {
    do { try await run() } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      exit(1)
    }
  }

  static func run() async throws {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    if options.help {
      print(
        """
        Usage: chroma-install [CONFIG.json] [--yes] [options]
        Without CONFIG, interactively discover an app, install it, and offer to save a config.
        Config paths resolve relative to the config file. Quit the app before reinstalling.
        Options:
          --prefix PATH              Linux prefix (default: ~/.local)
          --destination PATH         macOS .app destination (default: ~/Applications/NAME.app)
          --configuration MODE       release or debug
          --signing-identity NAME    macOS identity; '-' means local ad-hoc signing
          --yes                      Accept saved choices without prompts (requires CONFIG)
        """)
      return
    }
    let interactive = !options.yes && isatty(STDIN_FILENO) == 1
    guard interactive || (options.yes && options.config != nil) else {
      throw InstallError("Interactive setup requires a terminal. For automation provide CONFIG.json --yes.")
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let configURL = options.config.map { resolve($0, relativeTo: cwd) }
    let base: URL
    var config: Configuration
    if let configURL {
      config = try Configuration.load(configURL)
      base = configURL.deletingLastPathComponent()
    } else {
      let package = resolve(try prompt("Swift package directory", default: cwd.path), relativeTo: cwd)
      let products = try await discoverProducts(package)
      guard !products.isEmpty else { throw InstallError("No executable products found in \(package.path).") }
      print("Executable products: \(products.joined(separator: ", "))")
      let product = try prompt("Product", default: products[0])
      guard products.contains(product) else { throw InstallError("Choose one of the listed products.") }
      let name = try prompt("App name", default: product)
      config = Configuration(
        product: product, displayName: name,
        identifier: try prompt("App identifier", default: "local.\(product)"))
      config.macOSDestination = "~/Applications/\(product).app"
      base = package
    }
    if let value = options.overrides["--configuration"] { config.configuration = value }
    if let value = options.overrides["--prefix"] { config.linuxPrefix = value }
    if let value = options.overrides["--destination"] { config.macOSDestination = value }
    if let value = options.overrides["--signing-identity"] { config.signingIdentity = value }
    if interactive {
      config.configuration = try prompt("Build configuration", default: config.configuration)
      #if os(Linux)
      config.linuxPrefix = try prompt("Install prefix", default: config.linuxPrefix)
      #else
      config.macOSDestination = try prompt("App destination", default: config.macOSDestination)
      config.signingIdentity = try prompt("Signing identity ('-' for ad-hoc)", default: config.signingIdentity)
      #endif
    }
    try config.validate()
    let package = resolve(config.packagePath, relativeTo: base)
    let installer = try Installer(config: config, base: base)
    try installer.preflight()
    print(
      "\nInstall \(config.displayName) (\(config.identifier))\nPackage: \(package.path)\nProduct: \(config.product) (\(config.configuration))\nDestination: \(installer.destination.path)"
    )
    if interactive, !(try confirm("Build and install?")) { return }
    let products = try await discoverProducts(package)
    guard products.contains(config.product) else {
      throw InstallError("Package does not expose product \(config.product).")
    }
    var build = ["build", "--package-path", package.path, "-c", config.configuration]
    #if os(Linux)
    build += ["--build-system", "native", "--static-swift-stdlib"]
    #endif
    try await command("swift", build + ["--product", config.product])
    let bin = try await capture("swift", build + ["--show-bin-path"])
    try await installer.install(from: URL(fileURLWithPath: bin.trimmingCharacters(in: .whitespacesAndNewlines)))
    print("Installed \(config.displayName) at \(installer.destination.path)")
    if interactive,
      try confirm("Save these choices to \(configURL?.path ?? base.appendingPathComponent("chroma-config.json").path)?")
    {
      let output = configURL ?? base.appendingPathComponent("chroma-config.json")
      if FileManager.default.fileExists(atPath: output.path),
        !(try confirm("Replace existing config?", defaultYes: false))
      {
        return
      }
      try config.save(output)
      print("Saved \(output.path)")
    }
  }
}

func prompt(_ label: String, default value: String) throws -> String {
  print("\(label) [\(value)]: ", terminator: "")
  guard let line = readLine() else { throw InstallError("Input ended; installation cancelled.") }
  return line.isEmpty ? value : line
}

func confirm(_ label: String, defaultYes: Bool = true) throws -> Bool {
  while true {
    let answer = try prompt(label + " (y/n)", default: defaultYes ? "y" : "n").lowercased()
    if ["y", "yes"].contains(answer) { return true }
    if ["n", "no"].contains(answer) { return false }
  }
}

func capture(_ executable: String, _ arguments: [String]) async throws -> String {
  let result = try await Subprocess.run(
    .name(executable), arguments: .init(arguments), output: .string(limit: .max),
    error: .fileDescriptor(.standardError, closeAfterSpawningProcess: false))
  guard result.terminationStatus.isSuccess else {
    throw InstallError("\(executable) failed: \(result.terminationStatus)")
  }
  return result.standardOutput ?? ""
}

func command(_ executable: String, _ arguments: [String]) async throws {
  let result = try await Subprocess.run(
    .name(executable), arguments: .init(arguments),
    output: .fileDescriptor(.standardOutput, closeAfterSpawningProcess: false),
    error: .fileDescriptor(.standardError, closeAfterSpawningProcess: false))
  guard result.terminationStatus.isSuccess else {
    throw InstallError("\(executable) failed: \(result.terminationStatus)")
  }
}

func discoverProducts(_ package: URL) async throws -> [String] {
  struct Description: Decodable {
    struct Product: Decodable {
      let name: String
      let type: [String: [String]?]
    }
    let products: [Product]
  }
  let json = try await capture("swift", ["package", "--package-path", package.path, "describe", "--type", "json"])
  return try JSONDecoder().decode(Description.self, from: Data(json.utf8)).products
    .filter { $0.type.keys.contains("executable") }.map(\.name).sorted()
}
