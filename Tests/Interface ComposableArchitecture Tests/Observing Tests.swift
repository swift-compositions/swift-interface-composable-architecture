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
        let counter = Counter(
            increment: { _ in },
            observe: { request in
                ledger.record("observe \(request.start)")
                return AsyncThrowingStream { continuation in
                    continuation.yield(request.start + ledger.entries.count)
                    continuation.finish()
                }
            },
            read: { _ in 0 }
        )
        let store = TestStore(initialState: Observing<Counter.Observe>.State(.init(from: 10))) {
            Observing { counter.observe($0) }
        }
        while store.value == nil { await Task.yield() }
        store.expect { $0.value = 11 }
        #expect(ledger.entries == ["observe 10"])
        await store.dismount()
    }

    @Test func `a changed request restarts the stream`() async throws {
        let ledger = Ledger()
        let store = TestStore(initialState: Observing<Counter.Observe>.State(.init(from: 1))) {
            Observing { request in
                ledger.record("observe \(request.start)")
                return AsyncThrowingStream { continuation in
                    continuation.yield(request.start)
                    continuation.finish()
                }
            }
        }
        while store.value == nil { await Task.yield() }
        store.expect { $0.value = 1 }
        store.modify { $0.request.start = 2 }
        while store.value != 2 { await Task.yield() }
        store.expect { $0.value = 2 }
        #expect(ledger.entries == ["observe 1", "observe 2"])
        await store.dismount()
    }
}
