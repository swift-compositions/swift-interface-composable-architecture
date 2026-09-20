import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Reads interpretation policy from the feature body. Canonical coordinates are
/// supplied by Interface; TCA remains responsible for state/action machinery.
public struct Feature: MemberMacro {
    private struct Component {
        let kind: String
        let name: String
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let ext = declaration.as(ExtensionDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("Apply the interface Feature macro to a source extension of the domain type.")
        }
        let owner = ext.extendedType.trimmedDescription
        guard let body = ext.memberBlock.members.compactMap({ $0.decl.as(VariableDeclSyntax.self) })
            .flatMap({ $0.bindings }).first(where: { $0.pattern.trimmedDescription == "body" }),
            let block = body.accessorBlock,
            case let .getter(statements) = block.accessors else {
            throw MacroExpansionErrorMessage("Declare a computed body containing the domain's feature interpretation.")
        }
        func rootCall(_ expression: ExprSyntax) -> FunctionCallExprSyntax? {
            if let call = expression.as(FunctionCallExprSyntax.self) {
                if call.calledExpression.is(DeclReferenceExprSyntax.self) { return call }
                if let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base { return rootCall(base) }
            }
            if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base { return rootCall(base) }
            return nil
        }
        if statements.count == 1, let expression = statements.first?.item.as(ExprSyntax.self),
            let call = rootCall(expression),
            let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
            ["Requesting", "Listing", "Editing"].contains(name) {
            return try leaf(call, kind: name, owner: owner)
        }
        // A composition is an unconditional product. Conditional lifetime is
        // expressed with Presenting rather than syntax-dependent store shapes.
        func components(_ statements: CodeBlockItemListSyntax) throws -> [Component] {
            var result: [Component] = []
            for statement in statements {
                guard let expression = statement.item.as(ExprSyntax.self) else {
                    throw MacroExpansionErrorMessage("A feature composition contains Child, Presenting, Observing, or Features expressions.")
                }
                var call = expression.as(FunctionCallExprSyntax.self)
                while let member = call?.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base {
                    call = base.as(FunctionCallExprSyntax.self)
                }
                guard let call, let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else {
                    throw MacroExpansionErrorMessage("Use an explicit feature interpretation in the body.")
                }
                if name == "Features", let closure = call.trailingClosure {
                    result += try components(closure.statements)
                } else if name == "Children" {
                    for argument in call.arguments {
                        guard let path = argument.expression.as(KeyPathExprSyntax.self), path.components.count == 1,
                            let property = path.components.first?.component.as(KeyPathPropertyComponentSyntax.self) else {
                            throw MacroExpansionErrorMessage("Children selects direct canonical interface child key paths.")
                        }
                        result.append(Component(kind: "Child", name: property.declName.baseName.text))
                    }
                } else if ["Child", "Presenting"].contains(name) {
                    guard let path = call.arguments.first?.expression.as(KeyPathExprSyntax.self),
                        path.components.count == 1,
                        let property = path.components.first?.component.as(KeyPathPropertyComponentSyntax.self) else {
                        throw MacroExpansionErrorMessage("Select a direct domain child with a key path, such as Child(\\.read). Compose deeper children in their own feature.")
                    }
                    result.append(Component(kind: name, name: property.declName.baseName.text))
                } else if name == "Observing" {
                    guard call.arguments.count == 1, call.arguments.first?.expression.trimmedDescription == "self" else {
                        throw MacroExpansionErrorMessage("Use Observing(self) to interpret this domain's primary stream.")
                    }
                    result.append(Component(kind: name, name: "observation"))
                } else {
                    throw MacroExpansionErrorMessage("Unsupported composition component '\(name)'.")
                }
            }
            return result
        }
        let selections = try components(statements)
        guard !selections.isEmpty else {
            throw MacroExpansionErrorMessage("Select at least one domain interpretation.")
        }
        let hasObservation = selections.contains { $0.kind == "Observing" }
        let arguments = selections.map { component -> String in
            switch component.kind {
            case "Child": ".required(\(owner).Structure.\(component.name).self)"
            case "Presenting": ".presented(\(owner).Structure.\(component.name).self)"
            default: ".observing(\(owner).Primary.self)"
            }
        } + (hasObservation ? [] : ["calls: \(owner).Call.self"])
        let compositionAttribute = AttributeSyntax(stringLiteral: "@Composition(\(arguments.joined(separator: ", ")))")
        var result = try Composition.derive(
            of: compositionAttribute, providingMembersOf: ext, conformingTo: protocols, in: context, sourceBody: true
        )
        // Each source expression contributes exactly one piece of the product.
        // Calling is attached once, to the first piece, and observes the same
        // parent action. The wrapper's .dismiss runs before this whole product.
        for kind in ["Child", "Presenting"] {
            let matching = selections.filter { $0.kind == kind }
            guard !matching.isEmpty else { continue }
            let branches = matching.map { component -> String in
                let child = "\(owner).Structure.\(component.name)"
                var feature: String
                if kind == "Child" {
                    feature = "ComposableArchitecture2.Scope(\\.\(component.name), action: \\.\(component.name)) { self[keyPath: \(child).path] }"
                } else {
                    feature = "ComposableArchitecture2.EmptyFeature<State, Action>().ifLet(\\.\(component.name), action: \\.\(component.name)) { self[keyPath: \(child).path] }"
                }
                if !hasObservation, selections.first?.name == component.name {
                    feature += ".calling(\\.call, self, id: \\.writes)"
                }
                feature += ".interface(self)"
                return "if path == \(child).path { return ComposableArchitecture2.AnyFeature(\(feature)) }"
            }.joined(separator: "\n")
            result.append(DeclSyntax(stringLiteral: """
                public func \(kind)<Child: ComposableArchitecture2.FeatureProtocol>(
                    _ path: Swift.KeyPath<\(owner), Child>
                ) -> ComposableArchitecture2.AnyFeature<State, Action> {
                    \(branches)
                    preconditionFailure("Select a child declared in this feature body")
                }
                """))
        }
        let required = selections.filter { $0.kind == "Child" }
        if !required.isEmpty {
            let parameters = required.enumerated().map { "_ child\($0.offset): Swift.KeyPath<\(owner), Child\($0.offset)>" }
            result.append(DeclSyntax(stringLiteral: """
                public func Children<\(required.indices.map { "Child\($0): ComposableArchitecture2.FeatureProtocol" }.joined(separator: ", "))>(
                    \(parameters.joined(separator: ", "))
                ) -> some Feature {
                    ComposableArchitecture2.Features {
                        \(required.indices.map { "Child(child\($0))" }.joined(separator: "\n"))
                    }
                }
                """))
        }
        if hasObservation {
            result.append(DeclSyntax(stringLiteral: """
                public func Observing(_ owner: \(owner)) -> some Feature {
                    ComposableArchitecture2.Scope(\\.observation) {
                        Interface_ComposableArchitecture.Observing<\(owner).Primary>(owner)
                    }.interface(owner)
                }
                """))
        }
        return result
    }
    private static func leaf(_ call: FunctionCallExprSyntax, kind: String, owner: String) throws -> [DeclSyntax] {
        if kind == "Requesting" {
            guard call.arguments.count == 1, call.arguments.first?.expression.trimmedDescription == "self" else {
                throw MacroExpansionErrorMessage("Use Requesting(self) for this domain's request interpretation.")
            }
            return [
                DeclSyntax(stringLiteral: "public typealias State = Interface_ComposableArchitecture.Requesting<\(owner).Primary>.State"),
                DeclSyntax(stringLiteral: "public typealias Action = \(owner).Call"),
                DeclSyntax(stringLiteral: """
                    public func Requesting(_ owner: \(owner)) -> Interface_ComposableArchitecture.Requesting<\(owner).Primary> {
                        Interface_ComposableArchitecture.Requesting<\(owner).Primary>(owner)
                    }
                    """),
            ]
        }
        let editingExpression = kind == "Listing"
            ? call.arguments.first(where: { $0.label?.text == "editing" })?.expression
            : call.arguments.last?.expression
        guard let editing = editingExpression?.as(KeyPathExprSyntax.self), editing.components.count == 1,
            let property = editing.components.first?.component.as(KeyPathPropertyComponentSyntax.self) else {
            throw MacroExpansionErrorMessage("Select the ancestor's editing policy with a direct property key path.")
        }
        let ownerLabel = kind == "Listing" ? "commands" : "in"
        let explicitOwner = call.arguments.first(where: { $0.label?.text == ownerLabel })?.expression.as(MemberAccessExprSyntax.self)?.base
        guard let ancestor = editing.root?.trimmedDescription ?? explicitOwner?.trimmedDescription else {
            throw MacroExpansionErrorMessage("Select a rooted editing key path, such as \\Reminders.editing.")
        }
        let name = property.declName.baseName.text
        let projection = "\(ancestor)._\(name.prefix(1).uppercased())\(name.dropFirst())"
        if kind == "Editing" {
            return [
                DeclSyntax(stringLiteral: "public typealias State = Interface_ComposableArchitecture.Editing<\(projection)>.State"),
                "public typealias Action = Swift.Never",
                DeclSyntax(stringLiteral: """
                    public func Editing<Editor: Interface_ComposableArchitecture.Editor<\(projection)>>(
                        in owner: \(ancestor).Type, _ policy: Swift.KeyPath<\(ancestor), Editor>
                    ) -> some Feature {
                        Interface_ComposableArchitecture.Inherited(owner) { $0[keyPath: policy] }
                    }
                    """),
            ]
        }
        guard let rows = call.arguments.first(where: { $0.label?.text == "rows" })?.expression.as(KeyPathExprSyntax.self) else {
            throw MacroExpansionErrorMessage("Listing explicitly selects the observed value's rows with a key path.")
        }
        let interpretation = "Interface_ComposableArchitecture.Listing<\(owner).Primary, \(ancestor).Call, _Rows>"
        let compact = call.arguments.allSatisfy { $0.label?.text != "commands" }
        let extraParameters = compact ? "" : "commands: \(ancestor).Type,"
        let deletionParameter = compact ? "" : ", deleting: Swift.KeyPath<\(ancestor).Call, _Rows.Draft.Record.ID?>"
        let construction = compact
            ? "\(interpretation)(query, rows: rows, editing: editing, deleting: \(projection).deletedID)"
            : "\(interpretation)(query, rows: rows, commands: commands, editing: editing, deleting: deleting)"
        return [
            DeclSyntax(stringLiteral: """
                public enum _Rows: Interface_ComposableArchitecture.Rows {
                    public typealias Value = \(owner).Primary.Output.Element
                    public typealias Draft = \(projection)
                    public static var rows: Swift.KeyPath<Value, [Draft.Record]> { \(rows) }
                }
                """),
            DeclSyntax(stringLiteral: "public typealias State = \(interpretation).State"),
            DeclSyntax(stringLiteral: "public typealias Action = \(ancestor).Call"),
            DeclSyntax(stringLiteral: """
                public func Listing<Editor: Interface_ComposableArchitecture.Editor<\(projection)>>(
                    _ query: \(owner),
                    rows: Swift.KeyPath<_Rows.Value, [_Rows.Draft.Record]>,
                    \(extraParameters)
                    editing: Swift.KeyPath<\(ancestor), Editor>\(deletionParameter)
                ) -> \(interpretation) {
                    \(construction)
                }
                """),
        ]
    }

}
