import ComposableArchitecture2
import Interface_ComposableArchitecture
import Testing

// The parent action is an ordinary value, not an enum with a CasePathable marker.
private struct PlainAction { var value: Int }
@ComposableArchitecture2.Feature private struct PlainParent {
    struct State {
        var permanent = 0
        var presented: Int? = 1
    }
    typealias Action = PlainAction
    let ledger: Ledger
    var body: some Feature {
        Scope(\.permanent) { EmptyFeature<Int, Never>() }
        EmptyFeature<State, Action>()
            .ifLet(\.presented) {
                EmptyFeature<Int, Never>().onDismount { ledger.record("dismissed") }
            }
    }
}

@MainActor @Test private func actionlessPresentationNeedsNoParentOpticsConformance() async throws {
    let ledger = Ledger()
    let store = Store(initialState: PlainParent.State()) { PlainParent(ledger: ledger) }
    let child = try #require(store.scope(\.presented))
    child[dynamicMember: \.self] = 42
    #expect(store.state.presented == 42)
    store.presented = nil
    for _ in 0..<100 where ledger.entries.isEmpty { await Task.yield() }
    #expect(ledger.entries == ["dismissed"])
    #expect(store.scope(\.presented) == nil)
}

#if canImport(SwiftUI)
import SwiftUI

@MainActor @Test private func actionlessBindingSharesTheInstalledPresentationAndDismissesIt() async throws {
    let ledger = Ledger()
    @Bindable var store = Store(initialState: PlainParent.State()) { PlainParent(ledger: ledger) }
    let presentation = $store.scope(\.presented)
    let child = try #require(presentation.wrappedValue)
    child[dynamicMember: \.self] = 17
    #expect(store.state.presented == 17)
    presentation.wrappedValue = nil
    for _ in 0..<100 where ledger.entries.isEmpty { await Task.yield() }
    #expect(store.state.presented == nil)
    #expect(ledger.entries == ["dismissed"])
}
#endif
