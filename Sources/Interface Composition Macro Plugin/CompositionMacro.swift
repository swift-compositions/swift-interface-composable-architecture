import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Only interpretation policy is analyzed here. @Interface owns descriptors and
/// @Feature owns TCA derivation; neither package's Core is imported or reproduced.
public struct CompositionMacro: MemberMacro {
    struct Selection {
        let kind: String
        let type: String
        let name: String
        let initial: String?
        var feature: String { "\(type).Value" }
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try derive(of: node, providingMembersOf: declaration, conformingTo: protocols, in: context, sourceBody: false)
    }

    static func derive(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext,
        sourceBody: Bool
    ) throws -> [DeclSyntax] {
        guard let declaration = declaration.as(ExtensionDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@FeatureComposition requires a source extension of the interface being interpreted.")
        }
        let owner = declaration.extendedType.trimmedDescription
        let existing = declaration.memberBlock.members.compactMap { member -> String? in
            if let type = member.decl.as(StructDeclSyntax.self) { return type.name.text }
            if let type = member.decl.as(EnumDeclSyntax.self) { return type.name.text }
            if let type = member.decl.as(TypeAliasDeclSyntax.self) { return type.name.text }
            return nil
        }
        guard Set(existing).isDisjoint(with: ["State", "Action", "Scopes", "_Composition"]) else {
            throw MacroExpansionErrorMessage("@FeatureComposition owns State, Action, Scopes, and _Composition; declare interpretation policies instead.")
        }
        func metatype(_ expression: ExprSyntax) throws -> String {
            guard let access = expression.as(MemberAccessExprSyntax.self),
                access.declName.baseName.text == "self", let base = access.base else {
                throw MacroExpansionErrorMessage("Use an explicit interface descriptor or operation type followed by .self.")
            }
            return base.trimmedDescription
        }
        let arguments = node.arguments?.as(LabeledExprListSyntax.self) ?? []
        var selections: [Selection] = []
        var calls: String?
        for argument in arguments {
            if argument.label?.text == "calls" {
                guard !argument.expression.is(NilLiteralExprSyntax.self) else { continue }
                calls = try metatype(argument.expression)
                continue
            }
            guard argument.label == nil,
                let call = argument.expression.as(FunctionCallExprSyntax.self),
                let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                ["required", "presented", "observing"].contains(member.declName.baseName.text),
                let first = call.arguments.first, first.label == nil,
                call.arguments.count <= 2,
                call.arguments.dropFirst().allSatisfy({ $0.label?.text == "initial" }) else {
                throw MacroExpansionErrorMessage("Choose .required(Member.self), .presented(Member.self), or .observing(Operation.self), with an optional initial value.")
            }
            let kind = member.declName.baseName.text
            guard kind != "presented" || call.arguments.count == 1 else {
                throw MacroExpansionErrorMessage("A presented child starts absent; its request is supplied when presented.")
            }
            let type = try metatype(first.expression)
            let name = kind == "observing" ? "observation" : String(type.split(separator: ".").last!)
            guard !["writes", "value", "call", "Projection", "observation"].contains(name) || kind == "observing" else {
                throw MacroExpansionErrorMessage("The selected member '\(name)' conflicts with composition runtime storage.")
            }
            guard !selections.contains(where: { $0.name == name }) else {
                throw MacroExpansionErrorMessage("Select '\(name)' only once in this interpretation.")
            }
            selections.append(Selection(kind: kind, type: type, name: name,
                initial: call.arguments.dropFirst().first?.expression.trimmedDescription))
        }
        let children = selections.filter { $0.kind != "observing" }
        let observing = selections.first { $0.kind == "observing" }
        let hasBody = declaration.memberBlock.members.contains { member in
            member.decl.as(VariableDeclSyntax.self)?.bindings.contains {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body"
            } ?? false
        }
        var stateMembers: [String] = []
        var initializers: [String] = []
        var assignments: [String] = []
        for child in children {
            let type = "\(child.feature).State\(child.kind == "presented" ? "?" : "")"
            let initial = child.kind == "presented" ? "nil" : child.initial ?? ".init()"
            stateMembers.append("public var \(child.name): \(type)\(child.kind == "presented" ? " = nil" : "")")
            initializers.append("\(child.name): \(type) = \(initial)")
            assignments.append("self.\(child.name) = \(child.name)")
        }
        if let observing {
            stateMembers.append("public var observation: Interface_ComposableArchitecture.Observing<\(observing.type)>.State")
            initializers.append("observation: Interface_ComposableArchitecture.Observing<\(observing.type)>.State = .init(\(observing.initial ?? ".init()"))")
            assignments.append("self.observation = observation")
            stateMembers.append("""
                public var value: \(observing.type).Output.Element? { observation.value }
                public subscript<Member>(dynamicMember path: Swift.KeyPath<\(observing.type).Output.Element, Member>) -> Member? {
                    observation.value?[keyPath: path]
                }
                """)
        }
        if calls != nil { stateMembers.append("@ComposableArchitecture2.StoreTaskID public var writes") }
        let cases = children.map { "case \($0.name)(\($0.feature).Action)" }
        let routing = children.filter { $0.kind == "required" }.map {
            """
            if let action = Interface_ComposableArchitecture.routeInterfaceCall(call, at: \\.\($0.name), through: \($0.feature).Action.self) {
                return .\($0.name)(action)
            }
            """
        }.joined(separator: "\n")
        let action: String
        if let calls {
            action = """
                public enum Action: Interface_ComposableArchitecture.InterfaceCalls, CasePaths.CasePathable {
                    case call(\(calls))
                    \(cases.joined(separator: "\n"))
                    public static func route(_ call: \(calls)) -> Self {
                        \(routing)
                        return .call(call)
                    }
                    public var interfaceCall: \(calls)? {
                        switch self {
                        case let .call(call): return call
                        \(children.map { child in
                            """
                            case let .\(child.name)(action):
                                guard let call = Interface_ComposableArchitecture.canonicalInterfaceCall(action, as: \(child.feature).Call.self) else { return nil }
                                return \(calls).cases.\(child.name).embed(call)
                            """
                        }.joined(separator: "\n"))
                        }
                    }
                }
                """
        } else if cases.isEmpty {
            action = "public typealias Action = Swift.Never"
        } else {
            action = "public enum Action: CasePaths.CasePathable {\n\(cases.joined(separator: "\n"))\n}"
        }
        var scopes = children.filter { $0.kind == "required" }.map {
            "ComposableArchitecture2.Scope(\\.\($0.name), action: \\.\($0.name)) { owner[keyPath: \($0.type).path] }"
        }
        if let observing {
            scopes.append("ComposableArchitecture2.Scope(\\.observation) { Interface_ComposableArchitecture.Observing<\(observing.type)>(owner) }")
        }
        if scopes.isEmpty { scopes.append("ComposableArchitecture2.EmptyFeature<State, Action>()") }
        var body = "ComposableArchitecture2.Features {\n\(scopes.joined(separator: "\n"))\n}"
        if calls != nil { body += "\n.calling(\\.call, owner, id: \\.writes)" }
        for child in children where child.kind == "presented" {
            body += "\n.ifLet(\\.\(child.name), action: \\.\(child.name)) { owner[keyPath: \(child.type).path] }"
        }
        body += "\n.interface(owner)"
        if sourceBody { body = "owner.body" }
        let projectionMembers = children.filter { $0.kind == "required" }.map {
            """
            public var \($0.name): ComposableArchitecture2.Store<\($0.feature).State, \($0.feature).Action> {
                store.scope(\\.\($0.name), action: \\.\($0.name))
            }
            """
        }.joined(separator: "\n")
        let bindingMembers = children.map { child in
            if child.kind == "required" {
                return """
                public var \(child.name): Interface_ComposableArchitecture.ViewBindings<\(child.feature).State, \(child.feature).Action> {
                    .init(store.scope(\\.\(child.name), action: \\.\(child.name)))
                }
                """
            }
            return """
            public var \(child.name): Interface_ComposableArchitecture.PresentationBinding<\(child.feature).State, \(child.feature).Action> {
                Interface_ComposableArchitecture.ViewBindings(store).presenting(\\.\(child.name), action: \\.\(child.name))
            }
            """
        }.joined(separator: "\n")
        var result: [DeclSyntax] = [
            "public typealias State = _Composition.State",
            "public typealias Action = _Composition.Action",
            "public typealias Scopes = _Composition.Scopes",
            "public static var scopes: Scopes { _Composition.scopes }",
            "public var composition: _Composition { _Composition(owner: self) }",
        ]
        let declaresConformance = declaration.inheritanceClause?.inheritedTypes.contains {
            $0.type.trimmedDescription.split(separator: ".").last == "FeatureProtocol"
        } ?? false
        if declaresConformance && !hasBody { result.append("public var body: some Feature { composition }") }
        result.append(DeclSyntax(stringLiteral: """
            @ComposableArchitecture2.Feature
            public struct _Composition: ComposableArchitecture2.FeatureProtocol {
                \(observing == nil ? "" : "@dynamicMemberLookup")
                public struct State: Interface_ComposableArchitecture.InterfaceCompositionState, ComposableArchitecture2._FeatureState, ComposableArchitecture2.ValueObservable, DebugSnapshots.DebugSnapshotConvertible {
                    public typealias Feature = _Composition
                    public typealias Projection = _Composition.Projection
                    public typealias Bindings = _Composition.Bindings
                    \(stateMembers.joined(separator: "\n"))
                    public init(\(initializers.joined(separator: ", "))) {
                        \(assignments.joined(separator: "\n"))
                    }
                }
                \(action)
                let owner: \(owner)
                public var body: some Feature {
                    \(body)
                }
                @MainActor
                public struct Projection: Interface_ComposableArchitecture.InterfaceStoreProjection {
                    private let store: ComposableArchitecture2.Store<State, Action>
                    public init(_ store: ComposableArchitecture2.Store<State, Action>) { self.store = store }
                    \(projectionMembers)
                }
                @MainActor
                public struct Bindings: Interface_ComposableArchitecture.InterfaceStoreProjection {
                    private let store: ComposableArchitecture2.Store<State, Action>
                    public init(_ store: ComposableArchitecture2.Store<State, Action>) { self.store = store }
                    \(bindingMembers)
                }
            }
            """))
        return result
    }
}
