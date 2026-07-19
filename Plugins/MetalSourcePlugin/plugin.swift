import PackagePlugin

@main
struct MetalSourcePlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target
  ) async throws -> [Command] {
    guard let target = target as? SourceModuleTarget else { return [] }

    let input = target.directory.appending("Shaders/Renderer.metal")
    let output = context.pluginWorkDirectory.appending("MetalSource.generated.swift")
    let generator = try context.tool(named: "MetalSourceGenerator")

    return [
      .buildCommand(
        displayName: "Inlining Renderer.metal",
        executable: generator.path,
        arguments: [input.string, output.string],
        inputFiles: [input],
        outputFiles: [output]
      )
    ]
  }
}
