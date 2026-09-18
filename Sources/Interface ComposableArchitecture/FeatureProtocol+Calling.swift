public import ComposableArchitecture2

extension ComposableArchitecture2.FeatureProtocol where Action: CasePathable {
    // Actions that carry a Call are interpreted by the interface: each one becomes a task on `id`, so
    // the failure of a call is read from that task id.
    @warn_unqualified_access
    public func calling<Call, Path: CasePath<Action, Call>>(
        _ path: CaseKeyPath<Action, Path>,
        id: KeyPath<State, StoreTaskID>,
        _ interpret: @escaping (Call) async throws -> Void
    ) -> some ComposableArchitecture2.FeatureProtocol<State, Action> {
        self.modifier(Calling(path: path, id: id, interpret: interpret))
    }
}

private struct Calling<State, Action: CasePathable, Call, Path: CasePath<Action, Call>>: FeatureModifier {
    let path: CaseKeyPath<Action, Path>
    let id: KeyPath<State, StoreTaskID>
    let interpret: (Call) async throws -> Void
    let store = FeatureStore<State, Action>()

    func body(content: Content) -> some ComposableArchitecture2.FeatureProtocol<State, Action> {
        content
        ComposableArchitecture2.Update { state, action in
            guard let call = action[case: path] else { return }
            store.addTask(id: state[keyPath: id]) {
                try await interpret(call)
            }
        }
    }
}
