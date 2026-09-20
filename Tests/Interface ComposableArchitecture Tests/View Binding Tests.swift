import ComposableArchitecture2
import Interface_ComposableArchitecture
import SwiftUI
import Testing

@MainActor
@Suite struct `View bindings` {
    @Test func `nested presentation retains its own state and command lifetime`() async throws {
        let ledger = Ledger()
        let root = CompositionRoot(branch: CompositionBranch(
            reset: { _ in ledger.record("reset") },
            form: CompositionCommand { ledger.record("form \($0.value)") }
        ))
        let store = Store(initialState: CompositionRoot.State()) { root }
        @Stored<CompositionRoot> var injected = store
        store.branch.form = .init(7)
        let binding: Binding<StoreOf<CompositionCommand>?> = $injected.branch.form
        let child = try #require(binding.wrappedValue)
        @Stored<CompositionCommand> var form = child
        $form.request.wrappedValue = .init(42)
        #expect(store.state.branch.form?.request.value == 42)
        let sending = child.sending
        child.send()
        try await sending()
        #expect(ledger.entries == ["form 42"])
        #expect(binding.wrappedValue == nil)
        #expect(store.state.branch.form == nil)
        #expect(store.writes.taskError == nil)
        #expect(store.branch.writes.taskError == nil)
    }

    @Test func `presentation binding clears the installed child and can select a later child`() throws {
        let root = CompositionRoot(branch: CompositionBranch(reset: { _ in }, form: CompositionCommand { _ in }))
        let store = Store(initialState: CompositionRoot.State()) { root }
        @Stored<CompositionRoot> var injected = store
        let binding: Binding<StoreOf<CompositionCommand>?> = $injected.branch.form
        #expect(binding.wrappedValue == nil)
        store.branch.form = .init(7)
        #expect(binding.wrappedValue?.request.value == 7)
        binding.wrappedValue = nil
        #expect(store.state.branch.form == nil)
        store.branch.form = .init(19)
        #expect(binding.wrappedValue?.request.value == 19)
    }

    @Test func `view constructors retain the supplied input product and escaping intents`() {
        var taps = 0
        let view = ValueView(title: "A", tapped: { taps += 1 })
        #expect(view.suppliedTitle == "A")
        view.tap()
        #expect(taps == 1)
        func acceptsView<V: SwiftUI.View>(_ view: V) {}
        acceptsView(view)
        acceptsView(ExplicitView())
        let domain = CompositionCommand { _ in }
        let store = Store(initialState: CompositionCommand.State(3)) { domain }
        let form = CommandView(store: store, title: "Request")
        #expect(form.request == 3)
        store.request = .init(9)
        #expect(form.request == 9)
    }
}

@View private struct ValueView {
    private let title: String
    private let tapped: () -> Void
    @State private var count = 0
    @FocusState private var focused: Bool
    var body: some SwiftUI.View { Text(title) }
    var suppliedTitle: String { title }
    func tap() { tapped() }
}

@View(CompositionCommand.self) private struct CommandView {
    private let title: String
    var request: Int { store.request.value }
    var body: some SwiftUI.View { Text(title) }
}

@View private struct ExplicitView: SwiftUI.View {
    var body: some SwiftUI.View { EmptyView() }
}
