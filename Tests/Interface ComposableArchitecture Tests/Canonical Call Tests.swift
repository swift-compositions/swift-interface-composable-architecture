import ComposableArchitecture2
import ComposableArchitectureTestSupport
import Interface_ComposableArchitecture
import Interface_Macro
import Testing

// Deliberately has no CasePathable conformance. Interpretation consumes the
// Interface-owned call algebra; a consumer must not opt into a second optics API.
@Interface private struct CanonicalRequest: CanonicalRequest.Interface {
    enum Rejection: Error, Equatable { case refused }
    protocol Interface {
        func callAsFunction(_ value: Int) async throws(Rejection)
    }
}

@MainActor @Suite private struct CanonicalCallInterpretation {
    @Test func requestingExecutesAnUnadaptedCanonicalCall() async throws {
        let ledger = Ledger()
        let domain = CanonicalRequest { request in
            ledger.record("request \(request.value)")
        }
        let feature = Requesting(domain)
        let store = TestStore(initialState: .init(42)) { feature }
        store.send(.run(42))
        try await store.sending()
        #expect(ledger.entries == ["request 42"])
    }

    @Test func requestingPreservesTypedFailureWithoutAnOpticsAdapter() async throws {
        let domain = CanonicalRequest { _ throws(CanonicalRequest.Rejection) in throw .refused }
        let feature = Requesting(domain)
        let store = TestStore(initialState: .init(42)) { feature }
        store.send(.run(42))
        await #expect(throws: CanonicalRequest.Rejection.refused) { try await store.sending() }
        #expect(store.sending.taskError as? CanonicalRequest.Rejection == .refused)
        await store.dismount()
    }
}

@MainActor @Test private func observingInfersItsOperationFromTheDomainWithoutAnExpectedType() async throws {
    let domain = CompositionRead { _ in AsyncThrowingStream { $0.yield(42); $0.finish() } }
    let feature = Interface_ComposableArchitecture.Observing(domain)
    let store = TestStore(initialState: .init(.init())) { feature }
    while store.value == nil { await Task.yield() }
    store.expect { $0.value = 42 }
    #expect(store.value == 42)
    await store.dismount()
}

// Capabilities are declared using Swift protocols at the point of use.
extension CanonicalRequest.Run.Input: Hashable, Sendable {}
