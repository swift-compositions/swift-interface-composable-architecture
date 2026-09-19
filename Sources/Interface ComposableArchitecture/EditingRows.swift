public import ComposableArchitecture2
public import Operation
public import SwiftUI

/// Render a listing's existing rows with its selected editing interpretation.
/// Identity decides substitution; an unsaved draft appears once after the rows.
/// No row, request, action, or feature state is copied into a parallel model.
@MainActor
public struct EditingRows<
    Symbol: Operation::Operation.Operable, Call: Operation::Operation.Coproduct, Projection: ListingProjection,
    Row: SwiftUI.View, Editor: SwiftUI.View
>: SwiftUI.View where Symbol.Input: Copyable & Equatable, Symbol.Output: AsyncSequence,
    Symbol.Output.Element == Projection.Value, Call: Copyable {
    private let store: Store<Listing<Symbol, Call, Projection>.State, Call>
    private let row: (Projection.Draft.Record) -> Row
    private let editor: (Store<Editing<Projection.Draft>.State, Never>) -> Editor

    public init(
        _ store: Store<Listing<Symbol, Call, Projection>.State, Call>,
        @ViewBuilder row: @escaping (Projection.Draft.Record) -> Row,
        @ViewBuilder editor: @escaping (Store<Editing<Projection.Draft>.State, Never>) -> Editor
    ) {
        self.store = store
        self.row = row
        self.editor = editor
    }

    public var body: some SwiftUI.View {
        ForEach(store.rows) { value in
            if value.id == store.editing?.id, let child = store.scope(\.editing) {
                editor(child).id(value.id)
            } else {
                row(value)
            }
        }
        if store.editing?.original == nil, let child = store.scope(\.editing) {
            editor(child)
        }
    }
}
