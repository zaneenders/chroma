import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum TrackingMacro {}

extension TrackingMacro: MemberAttributeMacro {
  public static func expansion(
    of node: SwiftSyntax.AttributeSyntax,
    attachedTo declaration: some SwiftSyntax.DeclGroupSyntax,
    providingAttributesFor member: some SwiftSyntax.DeclSyntaxProtocol,
    in context: some SwiftSyntaxMacros.MacroExpansionContext
  ) throws -> [SwiftSyntax.AttributeSyntax] {
    guard !declaration.is(ActorDeclSyntax.self) else {
      throw TrackingMacroError.actorNotSupported
    }
    if declaration.as(ClassDeclSyntax.self) != nil {
      if let var_decl = member.as(VariableDeclSyntax.self) {
        guard var_decl.bindingSpecifier.trimmed.description == "var" else {
          return []  // only apply to variables
        }
        for attr in var_decl.attributes {
          switch attr {
          case .attribute(let attr_syntax):
            let _tracking_ignored = AttributeSyntax(
              attributeName: IdentifierTypeSyntax(name: .identifier("TrackerIgnored"))
            )
            if attr_syntax.trimmed == _tracking_ignored.trimmed {
              return []  // Filter out ignored properties
            }
          default:
            ()
          }
        }
        for binding in var_decl.bindings {
          if let accessor = binding.accessorBlock {
            switch accessor.accessors {
            case let .accessors(acc_list):
              for acc in acc_list {
                if acc.accessorSpecifier.tokenKind == .keyword(.get) {
                  return []  // skip computed properties
                }
              }
            default:
              ()
            }
          }
        }
        return [
          AttributeSyntax(
            leadingTrivia: .space,
            attributeName: IdentifierTypeSyntax(name: .identifier("Tracked")),
            trailingTrivia: .space
          )
        ]
      }
    }
    return []
  }
}

extension TrackingMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard !declaration.is(ActorDeclSyntax.self) else {
      throw TrackingMacroError.actorNotSupported
    }
    if declaration.as(ClassDeclSyntax.self) != nil {
      let _tracked: DeclSyntax = """
        @TrackerIgnored unowned var _$_tracker: Tracker?
        """
      return [_tracked]
    }
    return []
  }
}

extension TrackingMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard !declaration.is(ActorDeclSyntax.self) else {
      throw TrackingMacroError.actorNotSupported
    }
    if declaration.as(ClassDeclSyntax.self) != nil {
      let trackingExtension = try ExtensionDeclSyntax(
        "extension \(type.trimmed): TrackingMarker {}")
      return [trackingExtension]
    }
    return []
  }
}
