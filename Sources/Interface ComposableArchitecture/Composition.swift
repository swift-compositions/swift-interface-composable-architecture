public import ComposableArchitecture2
public import Interface_Macro
@_exported import Operation

/// Select lifetimes and interpretations of canonical interface coordinates.
/// Selection values are consumed by the macro; they store no runtime state.
public struct Selection {
    private init() {}

    public static func required<Member: Interface.Member>(_ member: Member.Type) -> Self { Self() }

    public static func required<Member: Interface.Member, Initial>(
        _ member: Member.Type, initial: Initial
    ) -> Self { Self() }

    public static func presented<Member: Interface.Member>(_ member: Member.Type) -> Self { Self() }

    public static func observing<Symbol: Operation.Operable>(
        _ symbol: Symbol.Type, initial: Symbol.Input? = nil
    ) -> Self where Symbol.Input: Copyable & Escapable & Equatable,
        Symbol.Output: AsyncSequence, Symbol.Output.Element: Copyable & Escapable { Self() }
}

/// Derives a product of selected child states and a sum of their routed actions.
/// Attach to a source extension of an existing interface. Child descriptors come
/// from @Interface; their types and owner projections are checked by the compiler.
/// TCA's @Feature owns state observation, case paths, scopes, and runtime machinery.
@attached(member, names: named(State), named(Action), named(Scopes), named(scopes), named(composition), named(body), named(_Composition))
public macro Composition(
    _ selections: Selection..., calls: Any.Type? = nil
) = #externalMacro(module: "Interface_Composition_Macro_Plugin", type: "Composition")

/// A store projection exposes required children as scoped stores. It refers to
/// the existing store, never a second copy of its state.
@MainActor
public protocol Scoping {
    associatedtype State
    associatedtype Action
    init(_ store: Store<State, Action>)
}

public protocol Composite {
    associatedtype Projection: Scoping where Projection.State == Self
    associatedtype Bindings: Scoping where Bindings.State == Self
}

extension Store where State: Composite, Action == State.Projection.Action {
    public subscript<ChildState, ChildAction>(
        dynamicMember path: KeyPath<State.Projection, Store<ChildState, ChildAction>>
    ) -> Store<ChildState, ChildAction> {
        State.Projection(self)[keyPath: path]
    }
}

/// Interpret a domain-first feature body using canonical Interface coordinates.
/// The source extension explicitly declares FeatureProtocol on current Swift.
@attached(member, names: named(State), named(Action), named(Scopes), named(scopes), named(composition), named(_Composition), named(Child), named(Children), named(Presenting), named(Observing), named(Requesting), named(Listing), named(Editing), named(_Rows))
public macro Feature() = #externalMacro(module: "Interface_Composition_Macro_Plugin", type: "Feature")

/// Derive the selected draft coordinate beside an existing domain editing policy.
/// The generated capability alias preserves the lens through an opaque result.
@attached(member, names: arbitrary)
public macro Editor() = #externalMacro(module: "Interface_Composition_Macro_Plugin", type: "Editor")
