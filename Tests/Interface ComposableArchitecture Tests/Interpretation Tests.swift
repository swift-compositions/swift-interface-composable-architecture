import ComposableArchitecture2
import CustomDump
import Interface_ComposableArchitecture
import Interface_Macro
import Testing

@MainActor @Test func genericCommandFeatureUsesTheCanonicalNestedCall() async throws {
    let ledger = Ledger()
    let domain = CounterDomain(counter: Counter(
        increment: { ledger.record("increment \($0.amount)") },
        observe: { _ in AsyncThrowingStream { $0.finish() } }, read: { _ in 42 }
    ))
    let store = Store(initialState: InterfaceFeature<CounterDomain.Call>.State()) {
        CounterDomain.Call.feature(domain)
    }
    store.counter.increment(by: 4)
    try await store.writes()
    expectNoDifference(ledger.entries, ["increment 4"])
}

@MainActor @Test func indexedExecutionRetainsOutputWithoutDismissing() async throws {
    let counter = Counter(increment: { _ in }, observe: { _ in AsyncThrowingStream { $0.finish() } }, read: { _ in 42 })
    let store = Store(initialState: Executing<Counter.Read>.State(.init())) { Counter.Read.executing(counter) }
    store.send(.execute)
    try await store.execution()
    expectNoDifference(store.result, 42)
    store.send(.execute)
    try await store.execution()
    expectNoDifference(store.result, 42)
}

@MainActor @Test func indexedExecutionRecordsFailure() async throws {
    let counter = Counter(
        increment: { _ throws(Counter.Failure) in throw .refused },
        observe: { _ in AsyncThrowingStream { $0.finish() } }, read: { _ in 0 }
    )
    let store = Store(initialState: Executing<Counter.Increment>.State(.init(by: 1))) {
        Executing<Counter.Increment>(counter)
    }
    store.send(.execute)
    await #expect(throws: Counter.Failure.refused) { try await store.execution() }
    #expect(store.result == nil)
    #expect(store.execution.taskError is Counter.Failure)
}

private struct ExtensionDomain { let counter: Counter }
@FeatureExtension
extension ExtensionDomain: FeatureProtocol {
    struct State {
        var operation: Executing<Counter.Read>.State? = .init(.init())
    }
    enum Action { case operation(Executing<Counter.Read>.Action) }
    var body: some Feature {
        EmptyFeature().ifLet(\.operation) { Counter.Read.executing(counter) }
    }
}

@MainActor @Test func sourceExtensionDerivesStateAndScopesWithoutStoredFeatureMachinery() async throws {
    let counter = Counter(increment: { _ in }, observe: { _ in AsyncThrowingStream { $0.finish() } }, read: { _ in 9 })
    let domain = ExtensionDomain(counter: counter)
    let store = Store(initialState: ExtensionDomain.State()) { domain }
    let child: StoreOf<Executing<Counter.Read>> = try #require(store.scope(\.operation))
    child.send(.execute)
    try await child.execution()
    expectNoDifference(child.result, 9)
    store.operation = nil
    #expect(store.operation == nil)
}


private struct DefaultExtensionDomain {}
@FeatureExtension
extension DefaultExtensionDomain: FeatureProtocol {
    struct State { var count = 0 }
    var body: some Feature { EmptyFeature() }
}

@MainActor @Test func sourceExtensionReusesTheDefaultActionDerivation() {
    let store = Store(initialState: DefaultExtensionDomain.State()) { DefaultExtensionDomain() }
    store.count = 2
    expectNoDifference(store.count, 2)
}
