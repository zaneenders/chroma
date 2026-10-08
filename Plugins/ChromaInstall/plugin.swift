import Foundation
import PackagePlugin

@main
struct ChromaInstall: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    if arguments == ["--help"] || arguments == ["-h"] {
      print(
        "Usage: swift package chroma-install [--without-profiling]\nBuild release and install the app. Profiling symbols are included by default."
      )
      return
    }
    guard arguments.isEmpty || arguments == ["--without-profiling"] else {
      throw InstallPluginError("Use chroma-install [--without-profiling]. No configuration file is needed.")
    }
    let products = context.package.products.compactMap { $0 as? ExecutableProduct }
    guard products.count == 1, let product = products.first else {
      throw InstallPluginError(
        "Expected one executable product for this platform; found: \(products.map(\.name).joined(separator: ", ")).")
    }
    let tool = try context.tool(named: "ChromaInstaller")
    let request = [context.package.directoryURL.path, product.name]
    try run(tool.url, arguments: request + arguments)

    var parameters = PackageManager.BuildParameters(configuration: .release, logging: .concise, echoLogs: true)
    let profiling = arguments.isEmpty
    parameters.otherSwiftcFlags = [profiling ? "-g" : "-gnone"]
    parameters.otherCFlags = [profiling ? "-g" : "-g0"]
    parameters.otherCxxFlags = parameters.otherCFlags
    #if os(Linux)
    parameters.otherSwiftcFlags.append("-static-stdlib")
    if !profiling { parameters.otherLinkerFlags = ["--strip-debug"] }
    #endif
    Diagnostics.remark("Building \(product.name) (release\(profiling ? ", with profiling symbols" : ""))")
    let build = try packageManager.build(.product(product.name), parameters: parameters)
    guard build.succeeded else { throw InstallPluginError("Build failed.\n\(build.logText)") }
    guard
      let executable = build.builtArtifacts.first(where: {
        $0.kind == .executable && $0.url.lastPathComponent == product.name
      })
    else { throw InstallPluginError("Build did not produce \(product.name).") }
    try run(tool.url, arguments: request + [executable.url.path] + arguments)
  }

  private func run(_ executable: URL, arguments: [String]) throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw InstallPluginError("Installer exited with status \(process.terminationStatus).")
    }
  }
}

private struct InstallPluginError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
