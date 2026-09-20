public import ComposableArchitecture2

extension FeatureProtocol where Action: Routed {
    /// Dismiss a matching presentation before executing the selected domain call.
    /// Matching forgets the store route; execution retains it. A failed command
    /// therefore does not restore the presentation or move its task to the root.
    public func dismiss<Presented, ID: Equatable>(
        _ presentation: WritableKeyPath<State, Presented?>,
        matching identity: KeyPath<Presented, ID?>,
        before operation: KeyPath<Action.Call, ID?>
    ) -> some Feature {
        self.modifier(Dismissal(presentation: presentation, identity: identity, operation: operation, discarding: false))
    }
    /// End the matching presentation without committing its owned edit sessions.
    public func discard<Presented: Discardable, ID: Equatable>(
        _ presentation: WritableKeyPath<State, Presented?>,
        matching identity: KeyPath<Presented, ID?>,
        before operation: KeyPath<Action.Call, ID?>
    ) -> some Feature {
        self.modifier(Dismissal(presentation: presentation, identity: identity, operation: operation, discarding: true))
    }

}

private struct Dismissal<State, Action: Routed, Presented, ID: Equatable>: FeatureModifier {
    let presentation: WritableKeyPath<State, Presented?>
    let identity: KeyPath<Presented, ID?>
    let operation: KeyPath<Action.Call, ID?>
    let discarding: Bool

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        ComposableArchitecture2.Update { state, action in
            guard let call = action.interfaceCall,
                let id = call[keyPath: operation],
                state[keyPath: presentation]?[keyPath: identity] == id
            else { return }
            if discarding, var value = state[keyPath: presentation] {
                discardPresentation(&value)
                state[keyPath: presentation] = value
            }
            state[keyPath: presentation] = nil
        }
        content
    }
}
