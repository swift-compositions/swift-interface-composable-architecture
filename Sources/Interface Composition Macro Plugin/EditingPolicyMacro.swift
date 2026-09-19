import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Derives a type-level witness for a selected lens. The domain record and its
/// operations remain unchanged; this macro owns only the editing relationship.
public struct EditingPolicyMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let ext = declaration.as(ExtensionDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@EditingPolicy requires an extension containing its editing property.")
        }
        let owner = ext.extendedType.trimmedDescription
        let properties = ext.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .flatMap { $0.bindings }
        guard properties.count == 1, let property = properties.first,
            let name = property.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            let block = property.accessorBlock, case let .getter(body) = block.accessors,
            body.count == 1,
            let call = body.first?.item.as(FunctionCallExprSyntax.self),
            call.calledExpression.trimmedDescription == "Editing" else {
            throw MacroExpansionErrorMessage("Declare one computed editing policy whose body is Editing(create:update:delete:draft:…).")
        }
        func argument(_ label: String) throws -> ExprSyntax {
            guard let value = call.arguments.first(where: { $0.label?.text == label })?.expression else {
                throw MacroExpansionErrorMessage("An editing policy explicitly selects '\(label)'.")
            }
            return value
        }
        func coordinate(_ label: String) throws -> String {
            let value = try argument(label)
            let name: String?
            if let reference = value.as(DeclReferenceExprSyntax.self) { name = reference.baseName.text }
            else if let member = value.as(MemberAccessExprSyntax.self), member.base?.trimmedDescription == "self" {
                name = member.declName.baseName.text
            } else { name = nil }
            guard let name else {
                throw MacroExpansionErrorMessage("Select '\(label)' using an existing direct domain property.")
            }
            return "\(owner).Structure.\(name).Value"
        }
        let create = try coordinate("create")
        let update = try coordinate("update")
        let delete = try coordinate("delete")
        guard let path = try argument("draft").as(KeyPathExprSyntax.self) else {
            throw MacroExpansionErrorMessage("Select the existing writable draft using a key path.")
        }
        let capitalized = name.prefix(1).uppercased() + name.dropFirst()
        let projection = "_\(capitalized)Draft"
        let record = path.root?.trimmedDescription ?? "\(create).Output"
        return [DeclSyntax(stringLiteral: """
            public enum \(projection): Interface_ComposableArchitecture.DraftProjection {
                public typealias Record = \(record)
                public typealias Draft = \(create).Input.Field
                public static var path: Swift.WritableKeyPath<Record, Draft> { \(path) }
            }
            """), DeclSyntax(stringLiteral: """
            public typealias \(capitalized)Feature = Interface_ComposableArchitecture.EditingFeature<\(projection)>
            """), DeclSyntax(stringLiteral: """
            public func Editing<Ignored: Swift.Error & Swift.Equatable>(
                create: \(create), update: \(update), delete: \(delete),
                draft: Swift.WritableKeyPath<\(projection).Record, \(projection).Draft>,
                blank: Interface_ComposableArchitecture.Editing<\(projection)>.BlankDraftPolicy = .save,
                ignoreUpdateFailure: Ignored
            ) -> Interface_ComposableArchitecture.Editing<\(projection)> {
                Interface_ComposableArchitecture.Editing<\(projection)>(
                    create: create, update: update, delete: delete, draft: draft,
                    blank: blank, ignoreUpdateFailure: ignoreUpdateFailure
                )
            }
            """)]
    }
}
