public import ComposableArchitecture2
public import Operation

extension ComposableArchitecture2.FeatureProtocol where Action: Operation.Coproduct {
    // A feature whose actions are an interface's calls: every action is run by the interface as a task on
    // `id`, so the failure of a call is read from that task id.
    @warn_unqualified_access
    public func calling(
        _ owner: Action.Owner,
        id: KeyPath<State, StoreTaskID>
    ) -> some ComposableArchitecture2.FeatureProtocol<State, Action> {
        self.modifier(Invocation(extract: { $0 }, id: id) { try await Action.run(owner, $0) })
    }
}

extension ComposableArchitecture2.FeatureProtocol where Action: CasePathable {
    // A feature some of whose actions carry an interface's call.
    @warn_unqualified_access
    public func calling<Call: Operation.Coproduct, Path: CasePath<Action, Call>>(
        _ path: CaseKeyPath<Action, Path>,
        _ owner: Call.Owner,
        id: KeyPath<State, StoreTaskID>
    ) -> some ComposableArchitecture2.FeatureProtocol<State, Action> {
        self.modifier(Invocation(extract: { $0[case: path] }, id: id) { try await Call.run(owner, $0) })
    }
}

private struct Invocation<State, Action, Call>: FeatureModifier {
    let extract: (Action) -> Call?
    let id: KeyPath<State, StoreTaskID>
    let interpret: (Call) async throws -> Void
    let store = FeatureStore<State, Action>()

    init(extract: @escaping (Action) -> Call?, id: KeyPath<State, StoreTaskID>, _ interpret: @escaping (Call) async throws -> Void) {
        self.extract = extract
        self.id = id
        self.interpret = interpret
    }

    func body(content: Content) -> some ComposableArchitecture2.FeatureProtocol<State, Action> {
        content
        ComposableArchitecture2.Update { state, action in
            guard let call = extract(action) else { return }
            store.addTask(id: state[keyPath: id]) {
                try await interpret(call)
            }
        }
    }
}
