public import ComposableArchitecture2
public import Operation

/// Execute an indexed operation without discarding its output. The request is its
/// canonical Input and the result retains its canonical Output, with no Any payload.
@ComposableArchitecture2.Feature public struct Executing<Symbol: Operation.Operable>
where Symbol.Input: Copyable, Symbol.Output: Copyable {
    public struct State {
        public var request: Symbol.Input
        public var result: Symbol.Output?
        @StoreTaskID public var execution
        public init(_ request: Symbol.Input) { self.request = request }
    }
    public enum Action { case execute }
    let owner: Symbol.Owner
    public init(_ owner: Symbol.Owner) { self.owner = owner }
    public var body: some Feature {
        Update { state, _ in
            guard !state.execution.isRunning else { return }
            let request = state.request
            store.addTask(id: state.execution) {
                let result = try await Symbol.run(owner, request)
                try store.modify { $0.result = result }
            }
        }
    }
}
