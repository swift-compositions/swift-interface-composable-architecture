import ComposableArchitecture2
import ComposableArchitectureTestSupport
import CustomDump
import Interface_ComposableArchitecture
import Testing

private struct Item: Identifiable, Equatable {
    struct Draft: Equatable { var title: String }
    let id: Int
    let created: Int
    var draft: Draft
}
private enum ItemDraft: Lens {
    typealias Record = Item
    typealias Draft = Item.Draft
    static var path: WritableKeyPath<Item, Item.Draft> { \.draft }
}
private enum EditFailure: Error { case missing, denied }

@Suite private struct EditingPolicies {
    let original = Item(id: 1, created: 123, draft: .init(title: "Original"))

    @Test func commitDistinguishesNewUnchangedChangedAndBlank() async throws {
        var events: [String] = []
        let feature = Editing<ItemDraft>(
            create: { draft in events.append("create \(draft.title)"); return Item(id: 2, created: 456, draft: draft) },
            update: { item in events.append("update \(item.id) \(item.created) \(item.draft.title)") },
            delete: { events.append("delete \($0)") },
            blank: .discardNewDeleteExisting { $0.title.isEmpty }
        )
        try await feature.commit(.init(original))
        try await feature.commit(.init(Item.Draft(title: "")))
        expectNoDifference(events, [])
        try await feature.commit(.init(Item.Draft(title: "New")))
        var changed = Editing<ItemDraft>.State(original)
        changed.title = "Changed"
        try await feature.commit(changed)
        changed.title = ""
        try await feature.commit(changed)
        expectNoDifference(events, ["create New", "update 1 123 Changed", "delete 1"])
    }

    @Test func blankValuesAreSavedUnlessAPolicySaysOtherwise() async throws {
        var created = false
        let feature = Editing<ItemDraft>(
            create: { draft in created = true; return Item(id: 2, created: 0, draft: draft) },
            update: { _ in }, delete: { _ in }
        )
        try await feature.commit(.init(Item.Draft(title: "")))
        #expect(created)
    }

    @Test func operationFailuresPropagate() async throws {
        var changed = Editing<ItemDraft>.State(original)
        changed.title = "Changed"
        let update = Editing<ItemDraft>(create: { _ in original }, update: { _ in throw EditFailure.denied }, delete: { _ in })
        await #expect(throws: EditFailure.denied) { try await update.commit(changed) }
        let create = Editing<ItemDraft>(create: { _ in throw EditFailure.missing }, update: { _ in }, delete: { _ in })
        await #expect(throws: EditFailure.missing) { try await create.commit(.init(Item.Draft(title: "New"))) }
        let delete = Editing<ItemDraft>(create: { _ in original }, update: { _ in },
            delete: { _ in throw EditFailure.denied }, blank: .discardNewDeleteExisting { $0.title.isEmpty })
        changed.title = ""
        await #expect(throws: EditFailure.denied) { try await delete.commit(changed) }
    }

    @MainActor @Test func manualCommitDoesNotSaveOnDismount() async throws {
        var events: [String] = []
        let feature = Editing<ItemDraft>(
            create: { draft in events.append(draft.title); return Item(id: 2, created: 0, draft: draft) },
            update: { _ in }, delete: { _ in }, commit: .manual, discard: .manual
        )
        let state = Editing<ItemDraft>.State(Item.Draft(title: "Draft"))
        let store = TestStore(initialState: state) { feature }
        await store.dismount()
        expectNoDifference(events, [])
        try await feature.commit(state)
        expectNoDifference(events, ["Draft"])
    }

    @MainActor @Test func dismountCommitsTheFinalDraftOnce() async throws {
        var events: [String] = []
        let feature = Editing<ItemDraft>(create: { draft in events.append(draft.title); return Item(id: 2, created: 0, draft: draft) },
            update: { _ in }, delete: { _ in })
        let store = TestStore(initialState: Editing<ItemDraft>.State(Item.Draft(title: "Before"))) { feature }
        store.modify { $0.title = "After" }
        await store.dismount()
        expectNoDifference(events, ["After"])
    }
}

@Test private func draftProjectionPreservesComplementaryFieldsAndLensLaws() {
    let original = Item(id: 1, created: 123, draft: .init(title: "Original"))
    var state = Editing<ItemDraft>.State(original)
    #expect(state.value == original)
    state.title = "Changed"
    #expect(state.value?.id == original.id)
    #expect(state.value?.created == original.created)
    #expect(state.value?.draft.title == "Changed")
    guard let value = state.value else {
        Issue.record("Editing lost the original record")
        return
    }
    let reconstructed = Editing<ItemDraft>.State(value)
    #expect(reconstructed.draft == state.draft)
    state.title = "Original"
    #expect(state.isSaved)
    #expect(state.value == original)
}

@Test private func discardingInvalidatesEarlierSessionSnapshots() async throws {
    var committed = false
    let feature = Editing<ItemDraft>(create: { draft in committed = true; return Item(id: 2, created: 0, draft: draft) },
        update: { _ in committed = true }, delete: { _ in committed = true })
    var state = Editing<ItemDraft>.State(Item.Draft(title: "Unsaved"))
    let capturedBeforeRemoval = state
    state.discard()
    try await feature.commit(capturedBeforeRemoval)
    #expect(!committed)
}
