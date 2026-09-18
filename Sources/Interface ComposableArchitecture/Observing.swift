public import ComposableArchitecture2
public import Operation

// A request kept under observation: the value follows the stream for the current request, and a
// new request restarts the stream.
@ComposableArchitecture2.Feature public struct Observing<Symbol: Operation.Symbol>
where Symbol.Input: Swift.Copyable & Swift.Escapable & Swift.Equatable, Symbol.Output: Swift.Copyable & Swift.Escapable {
    public struct State {
        public var request: Symbol.Input
        public var value: Symbol.Output?

        public init(request: Symbol.Input, value: Symbol.Output? = nil) {
            self.request = request
            self.value = value
        }
    }

    let observe: (Symbol.Input) -> AsyncThrowingStream<Symbol.Output, any Swift.Error>

    public init(_ observe: @escaping (Symbol.Input) -> AsyncThrowingStream<Symbol.Output, any Swift.Error>) {
        self.observe = observe
    }

    public var body: some ComposableArchitecture2.FeatureProtocol<State, Action> {
        ComposableArchitecture2.EmptyFeature()
            .onChange(of: store.request, initial: true) { _, request, _ in
                store.addTask {
                    for try await value in observe(request) {
                        try store.modify { $0.value = value }
                    }
                }
            }
    }
}
