public import ComposableArchitecture2
public import Operation

/// The command interpretation of any interface coproduct, including composed interfaces.
/// It uses the original Call as its action; per-operation outputs belong to Executing.
@ComposableArchitecture2.Feature public struct InterfaceFeature<Call: Operation.Coproduct> where Call: Copyable {
    public struct State {
        @StoreTaskID public var writes
        public init() {}
    }
    public typealias Action = Call
    let owner: Call.Owner
    public init(_ owner: Call.Owner) { self.owner = owner }
    public var body: some Feature {
        EmptyFeature().calling(owner, id: \.writes)
    }
}
