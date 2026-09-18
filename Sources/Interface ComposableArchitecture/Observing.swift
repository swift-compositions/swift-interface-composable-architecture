public import ComposableArchitecture2
public import Operation

// An observe operation's request kept under observation: the value follows the operation's sequence for
// the current request, and a new request restarts it.
@ComposableArchitecture2.Feature public struct Observing<Symbol: Operation.Symbol>
where
    Symbol.Input: Swift.Copyable & Swift.Escapable & Swift.Equatable,
    Symbol.Output: AsyncSequence,
    Symbol.Output.Element: Swift.Copyable & Swift.Escapable
{
    public struct State {
        public var request: Symbol.Input
        public var value: Symbol.Output.Element?

        public init(request: Symbol.Input, value: Symbol.Output.Element? = nil) {
            self.request = request
            self.value = value
        }
    }

    let observe: (Symbol.Input) -> Symbol.Output

    public init(_ observe: @escaping (Symbol.Input) -> Symbol.Output) {
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
