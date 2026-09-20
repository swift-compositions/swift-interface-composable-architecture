/// Lifecycle of a presentation which owns transactional editing sessions.
public protocol Discardable {
    mutating func discard()
}

public func discardPresentation<Value>(_ value: inout Value) {
    guard var presentation = value as? any Discardable else { return }
    presentation.discard()
    if let updated = presentation as? Value { value = updated }
}

extension Optional: Discardable where Wrapped: Discardable {
    public mutating func discard() { self?.discard() }
}
