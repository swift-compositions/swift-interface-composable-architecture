import ComposableArchitecture2
public import Operation

extension Operation.Coproduct where Self: Copyable & Escapable {
    /// Interpret the entire existing call algebra as a feature.
    public static func feature(_ owner: Owner) -> InterfaceFeature<Self> { .init(owner) }
}

extension Operation.Operable where Self: Copyable & Escapable, Input: Copyable, Output: Copyable {
    /// Execute this operation with typed request and result state.
    public static func executing(_ owner: Owner) -> Executing<Self> { .init(owner) }
}

extension Operation.Operable
where Self: Copyable & Escapable, Input: Copyable & Equatable, Output: AsyncSequence, Output.Element: Copyable & Escapable {
    /// Following a stream is an explicit interpretation, not an inferred command policy.
    public static func observing(_ owner: Owner) -> Observing<Self> { .init(owner) }
}

extension Operation.Composed where Self: Copyable & Escapable, Input: Copyable, Call: Copyable {
    /// Compose a request and dismiss on successful submission.
    public static func requesting(_ owner: Owner) -> Requesting<Self> { .init(owner) }
}
