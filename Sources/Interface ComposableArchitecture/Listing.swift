public import ComposableArchitecture2
public import Operation

/// A query result's row projection. The result remains the domain's original value.
public protocol ListingValue {
    associatedtype Row: EditableRecord
    var rows: [Row] { get }
}

/// Compose observation, canonical calls, and optional editing without a domain-specific
/// feature or a second action model. The deletion projection is supplied explicitly.
@Feature public struct Listing<Symbol: Operation.Operable, Call: Operation.Coproduct>
where
    Symbol.Input: Copyable & Equatable,
    Symbol.Output: AsyncSequence,
    Symbol.Output.Element: ListingValue,
    Call: Copyable & CasePathable
{
    public typealias Record = Symbol.Output.Element.Row
    public struct State {
        public var contents: Observing<Symbol>.State
        public var editing: Editing<Record>.State?
        @StoreTaskID public var writes
        public init(_ request: Symbol.Input) { self.contents = .init(request) }
        public init(_ field: Symbol.Input.Field) where Symbol.Input: Operation.Unary {
            self.contents = .init(field)
        }
        public var rows: [Record] {
            (contents.value?.rows ?? []).map { row in
                guard let editing, row.id == editing.id, let replacement = editing.value else { return row }
                return replacement
            }
        }
    }
    public typealias Action = Call
    let query: Symbol.Owner
    let commands: Call.Owner
    let editor: Editing<Record>
    let deletedID: (Call) -> Record.ID?
    public init(
        _ query: Symbol.Owner,
        commands: Call.Owner,
        editing: Editing<Record>,
        deleting deletedID: @escaping (Call) -> Record.ID?
    ) {
        self.query = query; self.commands = commands
        self.editor = editing; self.deletedID = deletedID
    }
    public var body: some Feature {
        Features {
            Update { state, action in
                if let id = deletedID(action), state.editing?.id == id { state.editing = nil }
            }
            Scope(\.contents) { Observing<Symbol>(query) }
        }
        .calling(commands, id: \.writes)
        .ifLet(\.editing) { editor }
    }
}
