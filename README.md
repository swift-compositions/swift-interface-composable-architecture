# swift-interface-composable-architecture

The bridge between an `@Interface` (swift-interface) and TCA26 (`ComposableArchitecture2`). Nothing here
is universal: the atoms and the macro know nothing of features or stores; this package is where the two meet.

| Type | What it is |
| --- | --- |
| `Observing<Symbol>` | A feature over an observe operation: `value` follows the operation's async sequence for `request`, and a new request restarts it. Takes the operation's arrow `(Input) -> Output` where `Output: AsyncSequence`. |
| `Requesting<Symbol>` | A feature whose state is a request being composed: `sendButtonTapped` sends it whole on the `sending` task id and dismisses on success. Takes the operation's arrow `(Input) async throws -> Output` — a closure over the interface's Input-typed witness, `{ try await reminders.lists.create($0) }`. |
| `FeatureProtocol.calling(_:id:_:)` | A modifier that runs the interface's interpreter for every action carrying a `Call`, as a task on the given id: `.calling(\.call, id: \.writes) { try await reminders($0) }`. |

`Symbol` is one of the `Operation.Symbol`s that `@Operations` declares beside an interface's protocol (`Reminders.Read.Page`); its `Input` is the operation's parameters as a value — the same value the interface
is called with, so a feature's state, its actions and the domain share one vocabulary.
