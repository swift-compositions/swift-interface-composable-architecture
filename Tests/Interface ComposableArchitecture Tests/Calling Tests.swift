import ComposableArchitecture2
import ComposableArchitectureTestSupport
import Interface_ComposableArchitecture
import Interface_Macro
import Testing

// A feature whose actions carry the counter's calls.
@Feature private struct Counting {
    struct State {
        @StoreTaskID var writes
    }

    enum Action {
        case call(Counter.Call)
        case noop
    }

    let counter: Counter

    var body: some FeatureProtocol<State, Action> {
        Update { _, action in
            switch action {
            case .call, .noop:
                break
            }
        }
        .calling(\.call, id: \.writes) { try await counter($0) }
    }
}

@MainActor
@Suite struct `Calling Tests` {
    // A call action reaches the interface's arrow, and its failure is recorded on the task id.
    @Test func `a call action reaches the arrow`() async throws {
        let ledger = Ledger()
        let counter = Counter(
            increment: { request throws(Counter.Failure) in
                guard request.amount > 0 else { throw .refused }
                ledger.record("increment \(request.amount)")
            },
            observe: { _ in AsyncThrowingStream { $0.finish() } },
            read: { _ in ledger.entries.count }
        )
        let store = TestStore(initialState: Counting.State()) { Counting(counter: counter) }
        store.send(.call(.increment(by: 2)))
        try await store.writes()
        #expect(ledger.entries == ["increment 2"])
        store.send(.call(.increment(by: 0)))
        await #expect(throws: Counter.Failure.refused) { try await store.writes() }
        #expect(store.writes.taskError as? Counter.Failure == .refused)
        store.send(.noop)
        await store.dismount()
    }
}
