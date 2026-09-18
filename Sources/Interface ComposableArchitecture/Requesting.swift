public import ComposableArchitecture2
public import Dependencies
public import Operation

// An operation's input being composed, then sent: the feature's actions are the calls of the operation's
// interface, each run on `sending`; a call that succeeds dismisses the feature, one that fails stays, its error
// on `sending`. `Requesting<Reminders.Lists.Create>(\.reminders.lists)` — the symbol names the input, the
// interface runs the calls.
@ComposableArchitecture2.Feature public struct Requesting<Symbol: Operation.Composed>
where
    Symbol.Input: Swift.Copyable & Swift.Escapable,
    Symbol.Call: Swift.Copyable & CasePathable
{
    // The state reads as the input it composes: `store.title` is `store.request.title`.
    @dynamicMemberLookup
    public struct State {
        public var request: Symbol.Input
        @StoreTaskID public var sending

        public init(_ request: Symbol.Input) {
            self.request = request
        }

        public subscript<Member>(dynamicMember keyPath: WritableKeyPath<Symbol.Input, Member>) -> Member {
            get { request[keyPath: keyPath] }
            set { request[keyPath: keyPath] = newValue }
        }
    }

    public typealias Action = Symbol.Call

    let interpret: (Action) async throws -> Void

    public init(_ owner: Symbol.Owner) {
        self.interpret = { try await Symbol.Call.run(owner, $0) }
    }

    // The interface is read from the dependencies each time a call is sent.
    public init(_ path: KeyPath<DependencyValues, Symbol.Owner> & Sendable) {
        self.interpret = { try await Symbol.Call.run(Dependency(path).wrappedValue, $0) }
    }

    public var body: some ComposableArchitecture2.FeatureProtocol<State, Action> {
        ComposableArchitecture2.Update { state, action in
            guard !state.sending.isRunning else { return }
            store.addTask(id: state.sending) {
                try await interpret(action)
                try store.dismiss()
            }
        }
    }
}

extension ComposableArchitecture2.Store {
    // A requesting feature has one thing to send: its request, as the operation's call.
    public func send<Symbol: Operation.Composed>() where State == Requesting<Symbol>.State, Action == Symbol.Call {
        send(Symbol.call(state.request))
    }
}
