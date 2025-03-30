import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum TrackedMacro {
  private static let _prefix: DeclSyntax = "_$_"
}

extension TrackedMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    var out: [DeclSyntax] = []
    if let var_decl = declaration.as(VariableDeclSyntax.self) {
      if let binding = var_decl.bindings.first {
        var str = ""
        if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier {
          str += "@TrackerIgnored private var \(_prefix)\(name)"
        }
        if let type = binding.typeAnnotation {
          str += "\(type)"
        }
        if let initializer = binding.initializer {
          str += "\(initializer)"
        }
        out.append(DeclSyntax(stringLiteral: str))
      }
    }
    return out
  }
}

extension TrackedMacro: AccessorMacro {
  public static func expansion(
    of node: SwiftSyntax.AttributeSyntax,
    providingAccessorsOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
    in context: some SwiftSyntaxMacros.MacroExpansionContext
  ) throws -> [SwiftSyntax.AccessorDeclSyntax] {
    if let var_decl = declaration.as(VariableDeclSyntax.self) {
      if let binding = var_decl.bindings.first {
        let name = binding.pattern.as(IdentifierPatternSyntax.self)
        let prefixed: AccessorDeclSyntax = "\(_prefix)\(name)"
        let initializer: AccessorDeclSyntax =
          """
          @storageRestrictions(initializes: \(prefixed))
          init(_old_value) {
              \(prefixed) = _old_value
          }
          """
        let getter: AccessorDeclSyntax =
          """
          get {
              if let _$_tracker {
                  _$_tracker.access()
              }
              return \(prefixed)
          }
          """
        let setter: AccessorDeclSyntax =
          """
          set {
              if let _$_tracker {
                  _$_tracker.mutating {
                      \(prefixed) = newValue
                  }
              } else {
                  \(prefixed) = newValue
              }
          }
          """
        return [initializer, getter, setter]
      }
    }
    return []
  }
}
