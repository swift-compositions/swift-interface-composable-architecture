import ComposableArchitecture2
import ComposableArchitectureTestSupport
import CustomDump
import Interface_ComposableArchitecture
import Testing

private struct Item: EditableRecord, Equatable {
    struct Draft: Equatable { var title: String }
    let id: Int
    let created: Int
    var draft: Draft
}
private enum EditFailure: Error { case missing, denied }

@Suite private struct EditingPolicies {
    let original = Item(id: 1, created: 123, draft: .init(title: "Original"))

    @Test func commitDistinguishesNewUnchangedChangedAndBlank() async throws {
        var events: [String] = []
        let feature = Editing<Item>(
            create: { draft in events.append("create \(draft.title)"); return Item(id: 2, created: 456, draft: draft) },
            update: { item in events.append("update \(item.id) \(item.created) \(item.draft.title)") },
            delete: { events.append("delete \($0)") },
            blank: .discardNewDeleteExisting { $0.title.isEmpty }
        )
        try await feature.commit(.init(original))
        try await feature.commit(.init(Item.Draft(title: "")))
        expectNoDifference(events, [])
        try await feature.commit(.init(Item.Draft(title: "New")))
        var changed = Editing<Item>.State(original)
        changed.title = "Changed"
        try await feature.commit(changed)
        changed.title = ""
        try await feature.commit(changed)
        expectNoDifference(events, ["create New", "update 1 123 Changed", "delete 1"])
    }

    @Test func blankValuesAreSavedUnlessAPolicySaysOtherwise() async throws {
        var created = false
        let feature = Editing<Item>(
            create: { draft in created = true; return Item(id: 2, created: 0, draft: draft) },
            update: { _ in }, delete: { _ in }
        )
        try await feature.commit(.init(Item.Draft(title: "")))
        #expect(created)
    }

    @Test func onlyExplicitlySelectedUpdateFailuresAreSuppressed() async throws {
        var changed = Editing<Item>.State(original)
        changed.title = "Changed"
        let ignored = Editing<Item>(create: { _ in original }, update: { _ in throw EditFailure.missing },
            delete: { _ in }, ignoreUpdateFailure: { $0 is EditFailure })
        try await ignored.commit(changed)
        let propagated = Editing<Item>(create: { _ in original }, update: { _ in throw EditFailure.denied }, delete: { _ in })
        await #expect(throws: EditFailure.denied) { try await propagated.commit(changed) }
        let creation = Editing<Item>(create: { _ in throw EditFailure.missing }, update: { _ in }, delete: { _ in },
            ignoreUpdateFailure: { _ in true })
        await #expect(throws: EditFailure.missing) { try await creation.commit(.init(Item.Draft(title: "New"))) }
    }

    @MainActor @Test func dismountCommitsTheFinalDraftOnce() async throws {
        var events: [String] = []
        let feature = Editing<Item>(create: { draft in events.append(draft.title); return Item(id: 2, created: 0, draft: draft) },
            update: { _ in }, delete: { _ in })
        let store = TestStore(initialState: Editing<Item>.State(Item.Draft(title: "Before"))) { feature }
        store.modify { $0.title = "After" }
        await store.dismount()
        expectNoDifference(events, ["After"])
    }
}
