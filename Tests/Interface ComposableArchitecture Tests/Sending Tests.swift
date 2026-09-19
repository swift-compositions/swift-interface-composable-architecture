import CasePaths
import ComposableArchitecture2
import Interface_ComposableArchitecture
import Interface_Macro
import Operation
import Testing

@Interface struct CounterDomain: CounterDomain.Interface {
    protocol Interface { var counter: Counter { get } }
}
extension CounterDomain.Call: CasePathable {}

@ComposableArchitecture2.Feature private struct DirectSending {
    struct State { @StoreTaskID var writes }
    typealias Action = CounterDomain.Call
    let domain: CounterDomain
    var body: some FeatureProtocol<State, Action> {
        EmptyFeature().calling(domain, id: \.writes)
    }
}

@ComposableArchitecture2.Feature private struct WrappedSending {
    struct State { @StoreTaskID var writes }
    enum Action: Calls { case call(CounterDomain.Call); case unrelated }
    let domain: CounterDomain
    var body: some FeatureProtocol<State, Action> {
        EmptyFeature().calling(\.call, domain, id: \.writes)
    }
}

@MainActor @Test func storePropertyNavigationSendsExactlyOneCanonicalCall() async throws {
    let ledger = Ledger()
    let domain = CounterDomain(counter: Counter(
        increment: { request in ledger.record("increment \(request.amount)") },
        observe: { _ in AsyncThrowingStream { $0.finish() } }, read: { _ in 0 }
    ))
    let direct = Store(initialState: DirectSending.State()) { DirectSending(domain: domain) }
    direct.counter.increment(by: 2)
    try await direct.writes()
    #expect(ledger.entries == ["increment 2"])
    let wrapped = Store(initialState: WrappedSending.State()) { WrappedSending(domain: domain) }
    wrapped.counter.increment(by: 3)
    try await wrapped.writes()
    #expect(ledger.entries == ["increment 2", "increment 3"])
}
