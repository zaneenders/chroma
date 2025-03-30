import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct TrackingMacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    TrackingMacro.self,
    TrackedMacro.self,
    TrackerIgnoredMacro.self,
  ]
}
