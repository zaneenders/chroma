import PackagePlugin

@main
struct ShaderSourcePlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    guard let target = target as? SourceModuleTarget else { return [] }
    let shaders: [(String, String)]
    switch target.name {
    case "MetalBackend":
      shaders = [("metalSource", "Renderer.metal")]
    case "WaylandBackend":
      shaders = [("vertexShader", "Renderer.vert"), ("fragmentShader", "Renderer.frag")]
    default:
      return []
    }
    let directory = target.directoryURL.appendingPathComponent("Shaders")
    let inputs = shaders.map { directory.appendingPathComponent($0.1) }
    let output = context.pluginWorkDirectoryURL.appendingPathComponent("Shaders.generated.swift")
    let generator = try context.tool(named: "ShaderSourceGenerator")
    return [
      .buildCommand(
        displayName: "Inlining \(target.name) shaders",
        executable: generator.url,
        arguments: [output.path] + zip(shaders, inputs).flatMap { [$0.0.0, $0.1.path] },
        inputFiles: inputs,
        outputFiles: [output]
      )
    ]
  }
}
