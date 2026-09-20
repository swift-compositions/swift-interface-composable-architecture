import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Derive view injection only. Layout, feature state, and business policy stay in source.
public struct ViewMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard declaration.is(StructDeclSyntax.self),
            member.is(VariableDeclSyntax.self) || member.is(FunctionDeclSyntax.self) else { return [] }
        let modifiers = member.as(VariableDeclSyntax.self)?.modifiers ?? member.as(FunctionDeclSyntax.self)!.modifiers
        let attributes = member.as(VariableDeclSyntax.self)?.attributes ?? member.as(FunctionDeclSyntax.self)!.attributes
        guard !modifiers.contains(where: { ["static", "class", "nonisolated"].contains($0.name.text) }),
            !attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "MainActor" }) else { return [] }
        return ["@MainActor"]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let view = declaration.as(StructDeclSyntax.self) else { return [] }
        let inheritsView = view.inheritanceClause?.inheritedTypes.contains {
            ["View", "SwiftUI.View", "SwiftUI::View"].contains($0.type.trimmedDescription)
        } ?? false
        guard !inheritsView else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): SwiftUI.View {}")]
    }

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
            members.append("@MainActor @Interface_ComposableArchitecture.ViewStore<\(raw: domain)> private var store: ComposableArchitecture2.StoreOf<\(raw: domain)>")
            parameters.append("store: ComposableArchitecture2.StoreOf<\(domain)>")
            assignments.append("self._store = Interface_ComposableArchitecture.ViewStore(wrappedValue: store)")
        }
        for member in declaration.memberBlock.members {
            guard !member.decl.is(InitializerDeclSyntax.self) else {
                throw MacroExpansionErrorMessage("@View derives the input initializer; remove the handwritten initializer.")
            }
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) else { continue }
            if !variable.attributes.isEmpty {
                let names = variable.attributes.compactMap { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription }
                guard names.count == 1,
                    ["State", "SwiftUI.State", "SwiftUI::State", "FocusState", "SwiftUI.FocusState", "SwiftUI::FocusState"].contains(names[0]) else {
                    throw MacroExpansionErrorMessage("@View supports @State and @FocusState local storage; other attributed inputs require explicit support.")
                }
                guard !variable.bindings.contains(where: { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "store" }),
                    variable.modifiers.contains(where: { $0.name.text == "private" }) else {
                    throw MacroExpansionErrorMessage("@View local state must be private and cannot be named store.")
                }
                continue
            }
            for binding in variable.bindings where binding.accessorBlock == nil {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                    let type = binding.typeAnnotation?.type else {
                    throw MacroExpansionErrorMessage("Declare each view input with a name and explicit type.")
                }
                guard name != "store" || domain == nil else {
                    throw MacroExpansionErrorMessage("@View(Domain.self) supplies store; do not redeclare it.")
                }
                if variable.bindingSpecifier.text == "let", binding.initializer != nil { continue }
                let escaping = type.is(FunctionTypeSyntax.self) ? "@escaping " : ""
                let initial = binding.initializer.map { " = \($0.value.trimmedDescription)" } ?? ""
                parameters.append("\(name): \(escaping)\(type.trimmedDescription)\(initial)")
                assignments.append("self.\(name) = \(name)")
            }
        }
        members.append(DeclSyntax(stringLiteral: """
        @MainActor \(access)init(\(parameters.joined(separator: ", "))) {
            \(assignments.joined(separator: "\n"))
        }
        """))
        return members
    }
}
