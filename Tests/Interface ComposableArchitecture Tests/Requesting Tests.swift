import ComposableArchitecture2
import ComposableArchitectureTestSupport
import Interface_ComposableArchitecture
import Interface_Macro
import Testing

@MainActor
@Suite struct `Requesting Tests` {
    // The sheet sends its request whole and dismisses itself when the send succeeds.
    @Test func `a successful send dismisses`() async throws {
        let ledger = Ledger()
        let store = TestStore(initialState: Requesting<Counter.Increment>.State(request: .init(by: 3))) {
            Requesting<Counter.Increment> { request in ledger.record("increment \(request.amount)") }
        }
        store.send(.sendButtonTapped)
        try await store.sending()
        #expect(ledger.entries == ["increment 3"])
        #expect(store.sending.taskError == nil)
    }

    // A failed send stays on the sheet, recorded on `sending`.
    @Test func `a failed send is recorded on sending`() async throws {
        let store = TestStore(initialState: Requesting<Counter.Increment>.State(request: .init(by: 3))) {
            Requesting<Counter.Increment> { _ in throw Counter.Failure.refused }
        }
        store.send(.sendButtonTapped)
        await #expect(throws: Counter.Failure.refused) { try await store.sending() }
        #expect(store.sending.taskError as? Counter.Failure == .refused)
        await store.dismount()
    }
}
