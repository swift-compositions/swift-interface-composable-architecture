public import ComposableArchitecture2
public import Operation

/// A selected collection projection and the editing lens for its existing rows.
/// Neither the result value nor the record adopts a bridge marker conformance.
public protocol ListingProjection {
    associatedtype Value
    associatedtype Draft: DraftProjection
    static var rows: KeyPath<Value, [Draft.Record]> { get }
}

/// Compose observation, canonical calls, and optional editing. Projections are
/// coordinates into original domain values; there is no second result model.
@ComposableArchitecture2.Feature public struct Listing<
    Symbol: Operation.Operable, Call: Operation.Coproduct, Projection: ListingProjection
> where Symbol.Input: Copyable & Equatable, Symbol.Output: AsyncSequence,
    Symbol.Output.Element == Projection.Value, Call: Copyable {
    public typealias Record = Projection.Draft.Record
    @dynamicMemberLookup
    public struct State {
        public var contents: Observing<Symbol>.State
        public var editing: Editing<Projection.Draft>.State?
        @StoreTaskID public var writes
        public init(_ request: Symbol.Input) { self.contents = .init(request) }
        public init(_ field: Symbol.Input.Field) where Symbol.Input: Operation.Unary {
            self.contents = .init(field)
        }
        public subscript<Member>(dynamicMember path: KeyPath<Symbol.Input, Member>) -> Member {
            contents.request[keyPath: path]
        }
        public subscript<Member>(dynamicMember path: WritableKeyPath<Symbol.Input, Member>) -> Member {
            get { contents.request[keyPath: path] }
            set { contents.request[keyPath: path] = newValue }
        }
        public var rows: [Record] {
            (contents.value?[keyPath: Projection.rows] ?? []).map { row in
                guard let editing, row.id == editing.id, let replacement = editing.value else { return row }
                return replacement
            }
        }
    }
    public typealias Action = Call
    @FeatureEnvironment(InterfaceContext<Call.Owner>.self) private var inheritedCommands
    private let query: Symbol.Owner
    private let explicitCommands: Call.Owner?
    private let editor: (Call.Owner) -> AnyFeature<Editing<Projection.Draft>.State, Never>
    private let deletedID: (Call) -> Record.ID?

    public init<Editor: EditingFeature<Projection.Draft>>(
        _ query: Symbol.Owner,
        commands: Call.Owner,
        editing: Editor,
        deleting deletedID: @escaping (Call) -> Record.ID?
    ) {
        self.query = query
        self.explicitCommands = commands
        self.editor = { _ in AnyFeature(editing) }
        self.deletedID = deletedID
    }

    /// Select the actual enclosing interface instance and an opaque editing
    /// capability. This never manufactures a domain implementation.
    public init<Editor: EditingFeature<Projection.Draft>>(
        _ query: Symbol.Owner,
        rows: KeyPath<Projection.Value, [Record]>,
        commands: Call.Owner.Type,
        editing: KeyPath<Call.Owner, Editor>,
        deleting deletedID: KeyPath<Call, Record.ID?>
    ) {
        precondition(rows == Projection.rows, "The listing and its state must use the same rows projection")
        self.query = query
        self.explicitCommands = nil
        self.editor = { AnyFeature($0[keyPath: editing]) }
        self.deletedID = { $0[keyPath: deletedID] }
    }

    private var commands: Call.Owner {
        guard let commands = explicitCommands ?? inheritedCommands else {
            preconditionFailure("Supply \(Call.Owner.self) with .interface(_:) before mounting this listing")
        }
        return commands
    }

    public var body: some Feature {
        Features {
            Update { state, action in
                if let id = deletedID(action), state.editing?.id == id { state.editing = nil }
            }
            Scope(\.contents) { Observing<Symbol>(query) }
        }
        .calling(commands, id: \.writes)
        .ifLet(\.editing) { editor(commands) }
    }
}
