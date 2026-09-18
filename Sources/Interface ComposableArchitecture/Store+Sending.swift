public import ComposableArchitecture2
public import Operation

// A store whose actions are an interface's calls reads as the interface: `store.delete(id)` and
// `store.update.complete(id, done)` are `store.send(.delete(id))` and `store.send(.update.complete(id, done))`.
// The sugar returns nothing and throws nothing — the call's outcome is on the task id it rides — which is what
// tells it apart from the live `try await reminders.delete(id)`.
extension ComposableArchitecture2.Store where Action: Operation.Sending {
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
}

extension ComposableArchitecture2.Store where Action: Calls {
    public subscript<Member>(dynamicMember keyPath: KeyPath<Action.Call.Sending, Member>) -> Member {
        Action.Call.sending { self.send(Action.call($0)) }[keyPath: keyPath]
    }
}
