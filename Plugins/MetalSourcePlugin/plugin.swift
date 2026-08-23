import PackagePlugin

@main
struct MetalSourcePlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target
  ) async throws -> [Command] {
    guard let target = target as? SourceModuleTarget else { return [] }

    let input = target.directoryURL.appendingPathComponent("Shaders/Renderer.metal")
    let output = context.pluginWorkDirectoryURL.appendingPathComponent("MetalSource.generated.swift")
    let generator = try context.tool(named: "MetalSourceGenerator")

    return [
      .buildCommand(
        displayName: "Inlining Renderer.metal",
        executable: generator.url,
        arguments: [input.path, output.path],
        inputFiles: [input],
        outputFiles: [output]
      )
    ]
  }
}
