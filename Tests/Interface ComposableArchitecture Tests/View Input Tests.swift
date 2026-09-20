import Interface_ComposableArchitecture
import Observation
import SwiftUI
import Testing

@Observable private final class InputSource { var count = 0 }

@View private struct BoundInput {
    @Binding private var count: Int
    var body: some SwiftUI.View { Text("\(count)") }
    func increment() { count += 1 }
}

@MainActor @Test private func derivedBindingInitializerPreservesTheOriginalStorage() {
    let source = InputSource()
    let view = BoundInput(count: Bindable(source).count)
    view.increment()
    #expect(source.count == 1)
    source.count = 9
    view.increment()
    #expect(source.count == 10)
}
