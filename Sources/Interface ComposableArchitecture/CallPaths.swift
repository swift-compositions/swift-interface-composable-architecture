public import CasePaths
import Either
public import Operation
public import Optic

// Optional adapter for clients explicitly using TCA's case-key-path APIs on canonical calls.
// The generic interpretations consume canonical calls directly and require no consumer conformance.
extension CasePathable where Self: Operation.Coproduct, AllCasePaths == CallPaths<Self> {
    public static var allCasePaths: CallPaths<Self> { CallPaths() }

    public var `case`: PartialCaseKeyPath<Self> { \.self }

    public static var _allCaseKeyPaths: [PartialCaseKeyPath<Self>] { [] }
}

@dynamicMemberLookup
public struct CallPaths<Call: Operation.Coproduct>: CasePath {
    public init() {}

    public func embed(_ value: Call) -> Call { value }

    public func extract(from root: Call) -> Call? { root }

    public subscript<Value>(
        dynamicMember keyPath: KeyPath<Call.Cases, Optic<Call, Call, Value, Value>.Case>
    ) -> CallPath<Call, Value> {
        CallPath(Call.cases[keyPath: keyPath])
    }
}

public struct CallPath<Call: Operation.Coproduct, Value>: CasePath {
    let optic: Optic<Call, Call, Value, Value>.Case

    init(_ optic: Optic<Call, Call, Value, Value>.Case) {
        self.optic = optic
    }

    public func embed(_ value: Value) -> Call { optic.embed(value) }

    public func extract(from root: Call) -> Value? {
        switch optic.match(root) {
        case let .right(value): value
        case .left: nil
        }
    }
}


/// A required child without a matching call interpretation contributes no route.
/// Concrete macro output selects these overloads using the child's actual Action.
public func routeInterfaceCall<Root: Operation.Coproduct, Child, Action>(
    _ root: Root,
    at path: KeyPath<Root.Cases, Optic<Root, Root, Child, Child>.Case>,
    through action: Action.Type
) -> Action? { nil }

/// A leaf whose action is its canonical call needs only the existing case prism.
public func routeInterfaceCall<Root: Operation.Coproduct, Action>(
    _ root: Root,
    at path: KeyPath<Root.Cases, Optic<Root, Root, Action, Action>.Case>,
    through action: Action.Type
) -> Action? {
    switch Root.cases[keyPath: path].match(root) {
    case let .right(call): call
    case .left: nil
    }
}

/// A composed child routes through its own selected interpretation recursively.
public func routeInterfaceCall<Root: Operation.Coproduct, Action: Calls>(
    _ root: Root,
    at path: KeyPath<Root.Cases, Optic<Root, Root, Action.Call, Action.Call>.Case>,
    through action: Action.Type
) -> Action? {
    switch Root.cases[keyPath: path].match(root) {
    case let .right(call): Action.route(call)
    case .left: nil
    }
}

/// An action unrelated to this domain operation contributes no canonical call.
public func canonicalInterfaceCall<Call, Action>(_ action: Action, as call: Call.Type) -> Call? { nil }

/// A leaf already uses the canonical call as its action.
public func canonicalInterfaceCall<Call>(_ action: Call, as call: Call.Type) -> Call? { action }

/// A selected composition can forget its route without executing or rerouting it.
public func canonicalInterfaceCall<Action: InterfaceCalls>(
    _ action: Action, as call: Action.Call.Type
) -> Action.Call? { action.interfaceCall }
