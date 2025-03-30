import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum TrackerIgnoredMacro {}

extension TrackerIgnoredMacro: AccessorMacro {
  public static func expansion(
    of node: SwiftSyntax.AttributeSyntax,
    providingAccessorsOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
    in context: some SwiftSyntaxMacros.MacroExpansionContext
  ) throws -> [SwiftSyntax.AccessorDeclSyntax] {
    []
  }
}
