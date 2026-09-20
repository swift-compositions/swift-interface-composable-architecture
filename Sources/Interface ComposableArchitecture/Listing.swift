public import ComposableArchitecture2
public import Operation

/// A selected collection projection and the editing lens for its existing rows.
/// Neither the result value nor the record adopts a bridge marker conformance.
public protocol Rows {
    associatedtype Value
    associatedtype Draft: Lens
    static var rows: KeyPath<Value, [Draft.Record]> { get }
}

/// Compose observation, canonical calls, and optional editing. Projections are
/// coordinates into original domain values; there is no second result model.
@ComposableArchitecture2.Feature public struct Listing<
    Symbol: Operation.Operable, Call: Operation.Coproduct, Projection: Rows
> where Symbol.Input: Copyable & Equatable, Symbol.Output: AsyncSequence,
    Symbol.Output.Element == Projection.Value, Call: Copyable {
    public typealias Record = Projection.Draft.Record
    @dynamicMemberLookup
    public struct State: Discardable {
        public mutating func discard() { editing?.discard() }
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
            contents.value?[keyPath: Projection.rows] ?? []
        }
    }
    public typealias Action = Call
    @FeatureEnvironment(Context<Call.Owner>.self) private var inheritedCommands
    private let query: Symbol.Owner
    private let explicitCommands: Call.Owner?
    private let editor: (Call.Owner, StoreTaskID) -> AnyFeature<Editing<Projection.Draft>.State, Never>
    private let discard: (Call.Owner) -> Editing<Projection.Draft>.Discard
    private let deletedID: (Call) -> Record.ID?

    public init<Policy: Editor<Projection.Draft>>(
        _ query: Symbol.Owner,
        commands: Call.Owner,
        editing: Policy,
        deleting deletedID: @escaping (Call) -> Record.ID?
    ) {
        self.query = query
        self.explicitCommands = commands
        self.editor = { _, writes in AnyFeature(Session(policy: editing, writes: writes)) }
        self.discard = { _ in editing.discard }
        self.deletedID = deletedID
    }

    /// Select the actual enclosing interface instance and an opaque editing
    /// capability. This never manufactures a domain implementation.
    public init<Policy: Editor<Projection.Draft>>(
        _ query: Symbol.Owner,
        rows: KeyPath<Projection.Value, [Record]>,
        commands: Call.Owner.Type,
        editing: KeyPath<Call.Owner, Policy>,
        deleting deletedID: KeyPath<Call, Record.ID?>
    ) {
        self.init(query, rows: rows, editing: editing, deleting: { $0[keyPath: deletedID] })
    }

    public init<Policy: Editor<Projection.Draft>>(
        _ query: Symbol.Owner, rows: KeyPath<Projection.Value, [Record]>,
        editing: KeyPath<Call.Owner, Policy>, deleting: @escaping (Call) -> Record.ID?
    ) {
        precondition(rows == Projection.rows, "The listing must use its canonical rows projection")
        self.query = query
        self.explicitCommands = nil
        self.editor = { owner, writes in AnyFeature(Session(policy: owner[keyPath: editing], writes: writes)) }
        self.discard = { $0[keyPath: editing].discard }
        self.deletedID = deleting
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
                if discard(commands) == .delete, let id = deletedID(action), state.editing?.id == id {
                    state.editing?.discard()
                    state.editing = nil
                }
            }
            Scope(\.contents) { Observing<Symbol>(query) }
        }
        .calling(commands, id: \.writes)
        .ifLet(\.editing) { editor(commands, store.writes) }
    }
}

/// Interprets only a session's selected termination policy. The listing owns the
/// task identity, so failures survive the removal of its optional editor.
private struct Session<Policy: Editor>: FeatureProtocol {
    typealias State = Policy.State
    typealias Action = Never
    let policy: Policy
    let writes: StoreTaskID
    let store = FeatureStore<State, Action>()

    var body: some Feature {
        EmptyFeature<State, Action>().onDismount {
            guard policy.commit == .dismiss, !store.state.isDiscarded else { return }
            do {
                try await withStoreTaskCancellation(id: writes) { try await policy.commit(store.state) }
            } catch {
                // The task identity retains the error for its owner to present.
            }
        }
    }
}
