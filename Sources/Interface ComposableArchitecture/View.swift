public import ComposableArchitecture2
public import SwiftUI
public import CasePaths

/// Derive construction from a view's input product. An optional feature argument
/// supplies its existing store and bindings; it never creates a feature or store.
@attached(member, names: named(store), named(_store), named($store), named(init))
public macro View(_ feature: Any.Type? = nil) = #externalMacro(
    module: "Interface_Composition_Macro_Plugin", type: "ViewMacro"
)

/// Inject one existing store. Reading it participates in SwiftUI observation;
/// its projection composes the feature's declared child coordinates.
@propertyWrapper @MainActor
public struct ViewStore<Domain: FeatureProtocol>: DynamicProperty {
    public let wrappedValue: StoreOf<Domain>
    public init(wrappedValue: StoreOf<Domain>) { self.wrappedValue = wrappedValue }
    public var projectedValue: ViewBindings<Domain.State, Domain.Action> { .init(wrappedValue) }
}

/// A coordinate adapter around the same store, not a second state representation.
@dynamicMemberLookup @MainActor
public struct ViewBindings<State, Action> {
    private let store: Store<State, Action>
    public init(_ store: Store<State, Action>) { self.store = store }

    @_disfavoredOverload
    public subscript<Member>(dynamicMember path: WritableKeyPath<State, Member>) -> Binding<Member> {
        Bindable(store)[dynamicMember: \Store<State, Action>.[dynamicMember: path]]
    }

    public func presenting<ChildState, Path: CasePath>(
        _ state: WritableKeyPath<State, ChildState?>,
        action: CaseKeyPath<Action, Path>
    ) -> Binding<Store<ChildState, Path.Value>?> {
        Bindable(store).scope(state, action: action)
    }
}

extension ViewBindings where State: InterfaceCompositionState, Action == State.Bindings.Action {
    public subscript<Member>(dynamicMember path: KeyPath<State.Bindings, Member>) -> Member {
        State.Bindings(store)[keyPath: path]
    }
}

/// Public spelling used by generated projections without requiring consumers to
/// import SwiftUI in the domain's Feature target.
public typealias PresentationBinding<State, Action> = Binding<Store<State, Action>?>

extension SwiftUI.View {
    /// Explicit UI policy: request focus when this field enters the view tree.
    public func focusOnPresentation() -> some SwiftUI.View {
        modifier(PresentationFocus())
    }
}

private struct PresentationFocus: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some SwiftUI.View {
        content.focused($focused).onAppear { focused = true }
    }
}
