import PackagePlugin

@main
struct WaylandSourcePlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target
  ) async throws -> [Command] {
    guard let target = target as? SourceModuleTarget else { return [] }

    let shaderDirectory = target.directoryURL.appendingPathComponent("Shaders")
    let vertexInput = shaderDirectory.appendingPathComponent("Renderer.vert")
    let fragmentInput = shaderDirectory.appendingPathComponent("Renderer.frag")
    let output = context.pluginWorkDirectoryURL.appendingPathComponent("WaylandShaders.generated.swift")
    let generator = try context.tool(named: "WaylandSourceGenerator")

    return [
      .buildCommand(
        displayName: "Inlining Wayland shaders",
        executable: generator.url,
        arguments: [vertexInput.path, fragmentInput.path, output.path],
        inputFiles: [vertexInput, fragmentInput],
        outputFiles: [output]
      )
    ]
  }
}
