public import ComposableArchitecture2
public import Interface_Macro
public import Operation

/// Select lifetimes and interpretations of canonical interface coordinates.
/// Selection values are consumed by the macro; they store no runtime state.
public struct FeatureSelection {
    private init() {}

    public static func required<Member: InterfaceMember>(_ member: Member.Type) -> Self { Self() }

    public static func required<Member: InterfaceMember, Initial>(
        _ member: Member.Type, initial: Initial
    ) -> Self { Self() }

    public static func presented<Member: InterfaceMember>(_ member: Member.Type) -> Self { Self() }

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
public macro FeatureComposition(
    _ selections: FeatureSelection..., calls: Any.Type? = nil
) = #externalMacro(module: "Interface_Composition_Macro_Plugin", type: "CompositionMacro")

/// A store projection exposes required children as scoped stores. It refers to
/// the existing store, never a second copy of its state.
@MainActor
public protocol InterfaceStoreProjection {
    associatedtype State
    associatedtype Action
    init(_ store: Store<State, Action>)
}

public protocol InterfaceCompositionState {
    associatedtype Projection: InterfaceStoreProjection where Projection.State == Self
}

extension Store where State: InterfaceCompositionState, Action == State.Projection.Action {
    public subscript<ChildState, ChildAction>(
        dynamicMember path: KeyPath<State.Projection, Store<ChildState, ChildAction>>
    ) -> Store<ChildState, ChildAction> {
        State.Projection(self)[keyPath: path]
    }
}
