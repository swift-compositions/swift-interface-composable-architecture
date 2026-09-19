public import ComposableArchitecture2
public import Interface_Macro
public import Operation

/// A selected writable projection of an existing record. The coordinate, not
/// the record, conforms. Assignment must preserve identity and complementary
/// fields and obey the get-put, put-get, and put-put lens laws. Records must
/// have value semantics: editing a copy must not mutate the saved original.
public protocol DraftProjection {
    associatedtype Record: Identifiable
    associatedtype Draft: Equatable
    static var path: WritableKeyPath<Record, Draft> { get }
}

/// Editing exposes its selected lens and commit semantics through an opaque
/// capability. A listing can compose it without knowing its implementation type.
public protocol EditingFeature<Projection>: FeatureProtocol
where State == Editing<Projection>.State, Action == Never {
    associatedtype Projection: DraftProjection
    func commit(_ state: State) async throws
}

/// A reusable interpretation of a record's draft lens and create/update/delete arrows.
/// Blank-draft behavior and suppressed update failures are explicit policies, not laws.
@ComposableArchitecture2.Feature public struct Editing<Projection: DraftProjection>: EditingFeature {
    public typealias Record = Projection.Record
    public typealias Draft = Projection.Draft
    @dynamicMemberLookup
    public struct State {
        public var draft: Draft
        public let original: Record?
        public init(_ draft: Draft) { self.draft = draft; self.original = nil }
        public init(_ original: Record) { self.draft = original[keyPath: Projection.path]; self.original = original }
        public var id: Record.ID? { original?.id }
        public var isSaved: Bool { original?[keyPath: Projection.path] == draft }
        public subscript<Value>(dynamicMember keyPath: WritableKeyPath<Draft, Value>) -> Value {
            get { draft[keyPath: keyPath] }
            set { draft[keyPath: keyPath] = newValue }
        }
        public var value: Record? {
            guard var value = original else { return nil }
            value[keyPath: Projection.path] = draft
            return value
        }
    }
    public typealias Action = Never

    public enum BlankDraftPolicy {
        /// Blank drafts are ordinary values; creation and update proceed normally.
        case save
        /// A blank new draft is discarded; a blank existing record is deleted.
        case discardNewDeleteExisting((Draft) -> Bool)
    }

    let create: (Draft) async throws -> Record
    let update: (Record) async throws -> Void
    let delete: (Record.ID) async throws -> Void
    let blank: BlankDraftPolicy
    let ignoreUpdateFailure: (any Error) -> Bool

    public init(
        create: @escaping (Draft) async throws -> Record,
        update: @escaping (Record) async throws -> Void,
        delete: @escaping (Record.ID) async throws -> Void,
        blank: BlankDraftPolicy = .save,
        ignoreUpdateFailure: @escaping (any Error) -> Bool = { _ in false }
    ) {
        self.create = create; self.update = update; self.delete = delete
        self.blank = blank; self.ignoreUpdateFailure = ignoreUpdateFailure
    }

    /// Typed operations retain their original request and result relationships.
    /// The selected error value is matched only against update failures; creation
    /// and deletion failures always propagate, including erased storage errors.
    public init<Create: InterfacePrimary, Update: InterfacePrimary, Delete: InterfacePrimary, Ignored: Error & Equatable>(
        create: Create,
        update: Update,
        delete: Delete,
        draft: WritableKeyPath<Record, Draft>,
        blank: BlankDraftPolicy = .save,
        ignoreUpdateFailure: Ignored
    ) where Create.Primary.Input: Operation.Unary,
        Create.Primary.Input.Field == Draft, Create.Primary.Output == Record,
        Update.Primary.Input: Operation.Unary, Update.Primary.Input.Field == Record,
        Update.Primary.Output == Void,
        Delete.Primary.Input: Operation.Unary, Delete.Primary.Input.Field == Record.ID,
        Delete.Primary.Output == Void {
        precondition(draft == Projection.path, "The editing state and policy must use the same selected draft lens")
        self.init(
            create: { try await Create.Primary.run(create, .init($0)) },
            update: { try await Update.Primary.run(update, .init($0)) },
            delete: { try await Delete.Primary.run(delete, .init($0)) },
            blank: blank,
            ignoreUpdateFailure: { ($0 as? Ignored) == ignoreUpdateFailure }
        )
    }

    /// The same policy used by the feature, also available to non-UI interpreters.
    public func commit(_ state: State) async throws {
        let isBlank: Bool
        switch blank {
        case .save: isBlank = false
        case let .discardNewDeleteExisting(predicate): isBlank = predicate(state.draft)
        }
        switch (state.original, isBlank) {
        case let (original?, true): try await delete(original.id)
        case (_?, false) where !state.isSaved:
            guard let value = state.value else { return }
            do { try await update(value) }
            catch { if !ignoreUpdateFailure(error) { throw error } }
        case (nil, false): _ = try await create(state.draft)
        case (_?, false), (nil, true): break
        }
    }

    public var body: some Feature {
        EmptyFeature().onDismount { try await commit(store.state) }
    }
}
