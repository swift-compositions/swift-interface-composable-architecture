public import ComposableArchitecture2

extension FeatureProtocol where Action: InterfaceCalls {
    /// Dismiss a matching presentation before executing the selected domain call.
    /// Matching forgets the store route; execution retains it. A failed command
    /// therefore does not restore the presentation or move its task to the root.
    public func dismiss<Presented, ID: Equatable>(
        _ presentation: WritableKeyPath<State, Presented?>,
        matching identity: KeyPath<Presented, ID?>,
        before operation: KeyPath<Action.Call, ID?>
    ) -> some Feature {
        self.modifier(DismissBeforeCall(presentation: presentation, identity: identity, operation: operation))
    }
}

private struct DismissBeforeCall<State, Action: InterfaceCalls, Presented, ID: Equatable>: FeatureModifier {
    let presentation: WritableKeyPath<State, Presented?>
    let identity: KeyPath<Presented, ID?>
    let operation: KeyPath<Action.Call, ID?>

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        ComposableArchitecture2.Update { state, action in
            guard let call = action.interfaceCall,
                let id = call[keyPath: operation],
                state[keyPath: presentation]?[keyPath: identity] == id
            else { return }
            state[keyPath: presentation] = nil
        }
        content
    }
}
