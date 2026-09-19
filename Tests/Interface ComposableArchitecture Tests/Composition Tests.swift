import DebugSnapshots
import CasePaths
import ComposableArchitecture2
import ComposableArchitectureTestSupport
import Interface_ComposableArchitecture
import Interface_Macro
import Operation
import Testing

@Interface struct CompositionCommand: CompositionCommand.Interface {
    protocol Interface { func callAsFunction(_ value: Int) async throws }
}
extension CompositionCommand.Call: CasePathable {}
extension CompositionCommand: FeatureProtocol {
    typealias State = Requesting<Run>.State
    typealias Action = Call
    var body: some Feature { Requesting<Run>(self) }
}

@Interface struct CompositionBranch: CompositionBranch.Interface {
    protocol Interface {
        var form: CompositionCommand { get }
        func reset() async throws
    }
}
extension CompositionBranch.Call: CasePathable {}
@FeatureComposition(
    .presented(CompositionBranch.Structure.form.self),
    calls: CompositionBranch.Call.self
)
extension CompositionBranch: FeatureProtocol {}

@Interface struct CompositionRoot: CompositionRoot.Interface {
    protocol Interface { var branch: CompositionBranch { get } }
}
extension CompositionRoot.Call: CasePathable {}
@FeatureComposition(
    .required(CompositionRoot.Structure.branch.self),
    calls: CompositionRoot.Call.self
)
extension CompositionRoot: FeatureProtocol {}

@Interface struct CompositionRead: CompositionRead.Interface {
    protocol Interface { func callAsFunction() -> AsyncThrowingStream<Int, any Error> }
}
@FeatureComposition(.observing(CompositionRead.Run.self))
extension CompositionRead: FeatureProtocol {}

@MainActor
@Suite struct `Composition Tests` {
    @Test func `required projection shares storage and sends once in the child lifetime`() async throws {
        let ledger = Ledger()
        let root = CompositionRoot(branch: CompositionBranch(
            reset: { _ in ledger.record("reset") },
            form: CompositionCommand { ledger.record("form \($0.value)") }
        ))
        let store = Store(initialState: CompositionRoot.State()) { root }
        let child: StoreOf<CompositionBranch> = store.branch
        child.form = .init(7)
        #expect(store.state.branch.form?.request.value == 7)
        store.branch.reset()
        try await child.writes()
        #expect(ledger.entries == ["reset"])
        #expect(!store.writes.isRunning)

        let form = try #require(child.scope(\.form))
        form.send()
        try await form.sending()
        #expect(store.state.branch.form == nil)
        #expect(ledger.entries == ["reset", "form 7"])
    }

    @Test func `property sending records errors on the scoped child's execution`() async throws {
        let root = CompositionRoot(branch: CompositionBranch(
            reset: { _ in throw Counter.Failure.refused },
            form: CompositionCommand { _ in }
        ))
        let store = Store(initialState: CompositionRoot.State()) { root }
        store.branch.reset()
        await #expect(throws: Counter.Failure.refused) { try await store.branch.writes() }
        #expect(store.branch.writes.taskError as? Counter.Failure == .refused)
        #expect(store.writes.taskError == nil)
    }

    @Test func `root and child routes retain distinct destinations`() async throws {
        let ledger = Ledger()
        let root = CompositionRoot(branch: CompositionBranch(
            reset: { _ in ledger.record("reset") },
            form: CompositionCommand { ledger.record("form \($0.value)") }
        ))
        let store = Store(initialState: CompositionRoot.State()) { root }
        store.send(.call(.branch.reset()))
        try await store.writes()
        store.send(.branch(.call(.reset())))
        try await store.branch.writes()
        #expect(ledger.entries == ["reset", "reset"])
    }

    @Test func `a failed nested request stays presented with its own error`() async throws {
        let root = CompositionRoot(branch: CompositionBranch(
            reset: { _ in },
            form: CompositionCommand { _ in throw Counter.Failure.refused }
        ))
        let store = Store(initialState: CompositionRoot.State()) { root }
        store.branch.form = .init(7)
        let form = try #require(store.branch.scope(\.form))
        form.send()
        await #expect(throws: Counter.Failure.refused) { try await form.sending() }
        #expect(store.state.branch.form?.request.value == 7)
        #expect(store.state.branch.form?.sending.taskError as? Counter.Failure == .refused)
        #expect(store.branch.writes.taskError == nil)
        #expect(store.writes.taskError == nil)
    }

    @Test func `observation is actionless and retains the operation result`() async throws {
        let store = TestStore(initialState: CompositionRead.State()) {
            CompositionRead { _ in AsyncThrowingStream { $0.yield(42); $0.finish() } }
        }
        while store.value == nil { await Task.yield() }
        store.expect { $0.observation.value = 42 }
        #expect(store.value == 42)
        let _: Never.Type = CompositionRead.Action.self
        await store.dismount()
    }
}
