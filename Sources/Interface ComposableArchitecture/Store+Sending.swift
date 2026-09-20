public import ComposableArchitecture2
public import Operation

// A store whose actions are an interface's calls reads as the interface: `store.delete(id)` and
// `store.update.complete(id, done)` are `store.send(.delete(id))` and `store.send(.update.complete(id, done))`.
// The sugar returns nothing and throws nothing — the call's outcome is on the task id it rides — which is what
// tells it apart from the live `try await reminders.delete(id)`.
extension ComposableArchitecture2.Store where Action: Operation.Sending {
    // Prefer scoped projections; Calls.route also preserves their execution
    // semantics when overload resolution chooses a canonical sender.
    @_disfavoredOverload
    public subscript<Member>(dynamicMember keyPath: KeyPath<Action.Sending, Member>) -> Member {
        Action.sending { self.send($0) }[keyPath: keyPath]
    }
}

// A feature whose own actions are an interface's calls, beside the actions of its children: the enum case that
// carries the call is the witness (`public enum Action: Calls { case call(Reminders.Call) … }`), and the store
// reads as the interface through it: `store.lists.delete(id)` is `store.send(.call(.lists.delete(id)))`.
public protocol Calls {
    associatedtype Call: Operation.Sending

    static func call(_ call: Call) -> Self
    static func route(_ call: Call) -> Self
}

extension Calls {
    public static func route(_ call: Call) -> Self { .call(call) }
}

extension ComposableArchitecture2.Store where Action: Calls {
    // Prefer scoped projections; Calls.route also preserves their execution
    // semantics when overload resolution chooses a canonical sender.
    @_disfavoredOverload
    public subscript<Member>(dynamicMember keyPath: KeyPath<Action.Call.Sending, Member>) -> Member {
        Action.Call.sending { self.send(Action.route($0)) }[keyPath: keyPath]
    }
}

/// A routed feature action can be projected back to its canonical domain call.
/// This forgets the route for policy matching only: dispatch still uses the
/// original action, preserving the selected child's task and error ownership.
public protocol Routed: Calls {
    var interfaceCall: Call? { get }
}
