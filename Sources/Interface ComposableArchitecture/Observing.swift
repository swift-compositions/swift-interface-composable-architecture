public import ComposableArchitecture2
public import Dependencies
public import Operation
public import Interface_Macro
public import SwiftUI

// An operation followed: `value` is the latest element of the sequence the operation yields for `request`,
// and a new request restarts it. `Observing(reminders.read.page)` selects the domain's canonical primary
// operation; its existing owner supplies the implementation. Every element lands in the animation the feature tree
// declares with `animation(_:)`, as sqlite-data's animated fetches do; without one, each lands as it comes.
@ComposableArchitecture2.Feature public struct Observing<Symbol: Operation::Operation.Operable>
where
    Symbol.Input: Swift.Copyable & Swift.Escapable & Swift.Equatable,
    Symbol.Output: AsyncSequence,
    Symbol.Output.Element: Swift.Copyable & Swift.Escapable
{
    // The state reads as its value: `store.overview.lists` is `store.overview.value?.lists`.
    @dynamicMemberLookup
    public struct State {
        public var request: Symbol.Input
        public var value: Symbol.Output.Element?

        public init(_ request: Symbol.Input, value: Symbol.Output.Element? = nil) {
            self.request = request
            self.value = value
        }

        // A one-field input is named by its field: `State(.list(id))` observes the page of that list.
        public init(_ field: Symbol.Input.Field) where Symbol.Input: Operation::Operation.Unary {
            self.request = .init(field)
        }

        public subscript<Member>(dynamicMember keyPath: KeyPath<Symbol.Output.Element, Member>) -> Member? {
            value?[keyPath: keyPath]
        }
    }

    public typealias Action = Never

    let observe: (Symbol.Input) async throws -> Symbol.Output
    @FeatureEnvironment(Delivery.self) private var animation

    public init(_ observe: @escaping (Symbol.Input) async throws -> Symbol.Output) {
        self.observe = observe
    }

    public init(_ owner: Symbol.Owner) {
        self.observe = { try await Symbol.run(owner, $0) }
    }

    /// Infer the canonical primary operation from the domain value. The operation
    /// symbol remains an implementation detail of this interpretation.
    public init<Domain: Interface.Primary>(_ domain: Domain) where Symbol == Domain.Primary {
        self.observe = { try await Symbol.run(domain, $0) }
    }

    // The owner is read from the dependencies each time the request is observed.
    public init(_ path: any KeyPath<DependencyValues, Symbol.Owner> & Sendable) {
        self.observe = { try await Symbol.run(Dependency(path).wrappedValue, $0) }
    }

    public var body: some ComposableArchitecture2.FeatureProtocol<State, Action> {
        ComposableArchitecture2.EmptyFeature()
            .onChange(of: store.request, initial: true) { _, request, _ in
                store.addTask {
                    for try await value in try await observe(request) {
                        try withAnimation(animation) { _ = try store.modify { $0.value = value } }
                    }
                }
            }
    }
}

extension FeatureProtocol {
    /// What every observation within this feature delivers lands in `animation`, as a binding's `animation()` lands
    /// what it sets. `animation()` names no SwiftUI type, so a Feature target need not import SwiftUI to animate.
    public func animation(_ animation: SwiftUI.Animation? = .default) -> some Feature {
        self.transformEnvironment { $0[Delivery.self] = animation }
    }
}

private enum Delivery: FeatureEnvironmentKey {
    static var liveValue: SwiftUI.Animation? { nil }
    static var testValue: SwiftUI.Animation? { nil }
}
