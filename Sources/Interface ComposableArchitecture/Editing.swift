public import ComposableArchitecture2

/// A writable draft projection. Implementations must preserve identity and all
/// complementary fields on assignment, and obey get-put, put-get, and put-put.
public protocol EditableRecord: Identifiable {
    associatedtype Draft: Equatable
    var draft: Draft { get set }
}

/// A reusable interpretation of a record's draft lens and create/update/delete arrows.
/// Blank-draft behavior and suppressed update failures are explicit policies, not laws.
@Feature public struct Editing<Record: EditableRecord> {
    @dynamicMemberLookup
    public struct State {
        public var draft: Record.Draft
        public let original: Record?
        public init(_ draft: Record.Draft) { self.draft = draft; self.original = nil }
        public init(_ original: Record) { self.draft = original.draft; self.original = original }
        public var id: Record.ID? { original?.id }
        public var isSaved: Bool { original?.draft == draft }
        public subscript<Value>(dynamicMember keyPath: WritableKeyPath<Record.Draft, Value>) -> Value {
            get { draft[keyPath: keyPath] }
            set { draft[keyPath: keyPath] = newValue }
        }
        public var value: Record? {
            guard var value = original else { return nil }
            value.draft = draft
            return value
        }
    }
    public typealias Action = Never

    public enum BlankDraftPolicy {
        /// Blank drafts are ordinary values; creation and update proceed normally.
        case save
        /// A blank new draft is discarded; a blank existing record is deleted.
        case discardNewDeleteExisting((Record.Draft) -> Bool)
    }

    let create: (Record.Draft) async throws -> Record
    let update: (Record) async throws -> Void
    let delete: (Record.ID) async throws -> Void
    let blank: BlankDraftPolicy
    let ignoreUpdateFailure: (any Error) -> Bool

    public init(
        create: @escaping (Record.Draft) async throws -> Record,
        update: @escaping (Record) async throws -> Void,
        delete: @escaping (Record.ID) async throws -> Void,
        blank: BlankDraftPolicy = .save,
        ignoreUpdateFailure: @escaping (any Error) -> Bool = { _ in false }
    ) {
        self.create = create; self.update = update; self.delete = delete
        self.blank = blank; self.ignoreUpdateFailure = ignoreUpdateFailure
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
