public import ComposableArchitecture2
public import Dependencies
public import Operation

// An operation followed: `value` is the latest element of the sequence the operation yields for `request`,
// and a new request restarts it. `Observing<Reminders.Read.Page>(reminders.read)` — the symbol names the
// operation, its owner runs it.
@ComposableArchitecture2.Feature public struct Observing<Symbol: Operation.Operable>
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

        public subscript<Member>(dynamicMember keyPath: KeyPath<Symbol.Output.Element, Member>) -> Member? {
            value?[keyPath: keyPath]
        }
    }

    public typealias Action = Never

    let observe: (Symbol.Input) async throws -> Symbol.Output

    public init(_ observe: @escaping (Symbol.Input) async throws -> Symbol.Output) {
        self.observe = observe
    }

    public init(_ owner: Symbol.Owner) {
        self.observe = { try await Symbol.run(owner, $0) }
    }

    // The owner is read from the dependencies each time the request is observed.
    public init(_ path: KeyPath<DependencyValues, Symbol.Owner> & Sendable) {
        self.observe = { try await Symbol.run(Dependency(path).wrappedValue, $0) }
    }

    public var body: some ComposableArchitecture2.FeatureProtocol<State, Action> {
        ComposableArchitecture2.EmptyFeature()
            .onChange(of: store.request, initial: true) { _, request, _ in
                store.addTask {
                    for try await value in try await observe(request) {
                        try store.modify { $0.value = value }
                    }
                }
            }
    }
}
