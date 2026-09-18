# swift-interface-composable-architecture

The bridge between an `@Interface` (swift-interface) and TCA26 (`ComposableArchitecture2`). Nothing here
is universal: the atoms and the macro know nothing of features or stores; this package is where the two meet.

| Type | What it is |
| --- | --- |
| `Observing<Symbol>` | A feature whose state is a request under observation: `value` follows the stream for `request`, and a new request restarts the stream. Takes the observe arrow `(Input) -> AsyncThrowingStream<Output, any Error>`. |
| `Requesting<Symbol>` | A feature whose state is a request being composed: `sendButtonTapped` sends it whole on the `sending` task id and dismisses on success. Takes the operation's arrow `(Input) async throws -> Output`. |
| `FeatureProtocol.calling(_:id:_:)` | A modifier that runs the interface's interpreter for every action carrying a `Call`, as a task on the given id: `.calling(\.call, id: \.writes) { try await reminders($0) }`. |

`Symbol` is an `Operation.Symbol` whose `Input` is the operation's `Request` — the same value the interface
is called with, so a feature's state, its actions and the domain share one vocabulary.
