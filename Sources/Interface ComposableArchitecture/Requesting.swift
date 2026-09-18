public import ComposableArchitecture2
public import Operation

// A request being composed: sent whole, at most once at a time; the feature dismisses itself when the
// send succeeds and keeps the failure on `sending` otherwise. Cancelling is the parent's to handle.
@ComposableArchitecture2.Feature public struct Requesting<Symbol: Operation.Symbol>
where Symbol.Input: Swift.Copyable & Swift.Escapable, Symbol.Output: Swift.Copyable & Swift.Escapable {
    public struct State {
        public var request: Symbol.Input
        @StoreTaskID public var sending

        public init(request: Symbol.Input) {
            self.request = request
        }
    }

    public enum Action {
        case cancelButtonTapped
        case sendButtonTapped
    }

    let send: (Symbol.Input) async throws -> Symbol.Output

    public init(_ send: @escaping (Symbol.Input) async throws -> Symbol.Output) {
        self.send = send
    }

    public var body: some ComposableArchitecture2.FeatureProtocol<State, Action> {
        ComposableArchitecture2.Update { state, action in
            switch action {
            case .cancelButtonTapped:
                break
            case .sendButtonTapped:
                guard !state.sending.isRunning else { break }
                let request = state.request
                store.addTask(id: state.sending) {
                    _ = try await send(request)
                    try store.dismiss()
                }
            }
        }
    }
}
