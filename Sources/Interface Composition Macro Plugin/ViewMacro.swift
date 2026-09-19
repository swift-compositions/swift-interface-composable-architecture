import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Derive view injection only. Layout, feature state, and business policy stay in source.
public struct ViewMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@View requires a view struct.")
        }
        let arguments = node.arguments?.as(LabeledExprListSyntax.self) ?? []
        var domain: String?
        if let argument = arguments.first {
            guard arguments.count == 1, argument.label == nil,
                let access = argument.expression.as(MemberAccessExprSyntax.self),
                access.declName.baseName.text == "self", let base = access.base else {
                throw MacroExpansionErrorMessage("Select an existing feature with @View(Domain.self), or use @View for value inputs.")
            }
            domain = base.trimmedDescription
        }
        let access = declaration.modifiers.contains { ["public", "open"].contains($0.name.text) } ? "public " : ""
        var parameters: [String] = []
        var assignments: [String] = []
        var members: [DeclSyntax] = []
        if let domain {
            members.append("@Interface_ComposableArchitecture.ViewStore<\(raw: domain)> private var store: ComposableArchitecture2.StoreOf<\(raw: domain)>")
            parameters.append("store: ComposableArchitecture2.StoreOf<\(domain)>")
            assignments.append("self._store = Interface_ComposableArchitecture.ViewStore(wrappedValue: store)")
        }
        for member in declaration.memberBlock.members {
            guard !member.decl.is(InitializerDeclSyntax.self) else {
                throw MacroExpansionErrorMessage("@View derives the input initializer; remove the handwritten initializer.")
            }
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) else { continue }
            for binding in variable.bindings where binding.accessorBlock == nil {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                    let type = binding.typeAnnotation?.type else {
                    throw MacroExpansionErrorMessage("Declare each view input with a name and explicit type.")
                }
                guard name != "store" || domain == nil else {
                    throw MacroExpansionErrorMessage("@View(Domain.self) supplies store; do not redeclare it.")
                }
                guard variable.attributes.isEmpty else {
                    throw MacroExpansionErrorMessage("@View inputs cannot have property wrappers; keep local UI state in a separate view or modifier.")
                }
                if variable.bindingSpecifier.text == "let", binding.initializer != nil { continue }
                let escaping = type.is(FunctionTypeSyntax.self) ? "@escaping " : ""
                let initial = binding.initializer.map { " = \($0.value.trimmedDescription)" } ?? ""
                parameters.append("\(name): \(escaping)\(type.trimmedDescription)\(initial)")
                assignments.append("self.\(name) = \(name)")
            }
        }
        members.append(DeclSyntax(stringLiteral: """
        \(access)init(\(parameters.joined(separator: ", "))) {
            \(assignments.joined(separator: "\n"))
        }
        """))
        return members
    }
}
