import ComposableArchitecture2
import ComposableArchitectureTestSupport
import Interface_ComposableArchitecture
import Interface_Macro
import Testing

@MainActor
@Suite struct `Observing Tests` {
    // The value follows the stream for the current request; a new request restarts it.
    @Test func `the value follows the request`() async throws {
        let ledger = Ledger()
        let store = TestStore(initialState: Observing<Counter.Operations.Read>.State(request: .init())) {
            Observing<Counter.Operations.Read> { request in
                ledger.record("observe")
                return AsyncThrowingStream { continuation in
                    continuation.yield(ledger.entries.count)
                    continuation.finish()
                }
            }
        }
        while store.value == nil { await Task.yield() }
        store.expect { $0.value = 1 }
        #expect(ledger.entries == ["observe"])
        await store.dismount()
    }

    @Test func `a changed request restarts the stream`() async throws {
        let ledger = Ledger()
        let store = TestStore(initialState: Observing<Counter.Operations.Increment>.State(request: .init(by: 1))) {
            Observing<Counter.Operations.Increment> { request in
                ledger.record("observe \(request.amount)")
                return AsyncThrowingStream { continuation in
                    continuation.yield(())
                    continuation.finish()
                }
            }
        }
        while store.value == nil { await Task.yield() }
        store.expect { $0.value = () }
        store.modify { $0.request.amount = 2 }
        while ledger.entries.count < 2 { await Task.yield() }
        #expect(ledger.entries == ["observe 1", "observe 2"])
        await store.dismount()
    }
}
