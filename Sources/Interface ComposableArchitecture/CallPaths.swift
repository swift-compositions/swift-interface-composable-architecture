public import CasePaths
import Either
public import Operation
public import Optic

// An interface's Call is CasePathable through its own optics: `\Reminders.Call.Cases.lists` is the `lists` case,
// `\.self` the Call itself. One line adopts it: `extension Reminders.Call: CasePathable {}`.
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

    /// The path of a child with no actions of its own (an `Observing`): nothing is ever extracted or embedded.
    public var never: NeverPath<Call> { NeverPath() }
}

public struct NeverPath<Call>: CasePath {
    public func embed(_ value: Never) -> Call {}

    public func extract(from root: Call) -> Never? { nil }
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
