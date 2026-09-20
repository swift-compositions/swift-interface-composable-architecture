public import ComposableArchitecture2

/// Lexically supplied interface implementation. Nested interpretations reuse the
/// enclosing model rather than looking up a second implementation globally.
public enum Context<Owner>: FeatureEnvironmentKey {
    public static var liveValue: Owner? { nil }
    public static var testValue: Owner? { nil }
}

extension FeatureProtocol {
    public func interface<Owner>(_ owner: Owner) -> some Feature {
        self.transformEnvironment { $0[Context<Owner>.self] = owner }
    }
}

/// Interpret a relationship that needs an enclosing interface's capabilities.
/// The root composition supplies that interface for the lifetime of its tree.
public struct Inherited<Owner, Content: FeatureProtocol>: FeatureProtocol {
    public typealias State = Content.State
    public typealias Action = Content.Action
    @FeatureEnvironment(Context<Owner>.self) private var owner
    private let content: (Owner) -> Content

    public init(_ owner: Owner.Type, content: @escaping (Owner) -> Content) {
        self.content = content
    }

    private var implementation: Owner {
        guard let owner else {
            preconditionFailure("Supply \(Owner.self) with .interface(_:) before mounting this interpretation")
        }
        return owner
    }

    public var body: some Feature { content(implementation) }
}
