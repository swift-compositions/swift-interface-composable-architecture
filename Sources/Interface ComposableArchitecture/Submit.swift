public import ComposableArchitecture2
public import Operation
public import SwiftUI

/// Submit the canonical request. Validation and labeling remain presentation policy;
/// execution, errors and successful dismissal belong to Requesting.
@MainActor
public struct Submit<Symbol: Operation::Operation.Composed>: SwiftUI.View
where Symbol.Input: Copyable & Escapable, Symbol.Call: Copyable {
    private let title: LocalizedStringKey
    private let store: Store<Requesting<Symbol>.State, Symbol.Call>
    private let allowing: Bool

    public init(
        _ title: LocalizedStringKey,
        store: Store<Requesting<Symbol>.State, Symbol.Call>,
        allowing: Bool = true
    ) {
        self.title = title
        self.store = store
        self.allowing = allowing
    }

    public var body: some SwiftUI.View {
        // A confirmation, as the system draws one: a checkmark, named by the title.
        SwiftUI.Button(role: .confirm) { store.send() } label: { SwiftUI.Label(title, systemImage: "checkmark") }
            .disabled(!allowing || store.sending.isRunning)
    }
}
