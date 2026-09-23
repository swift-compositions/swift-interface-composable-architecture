public import ComposableArchitecture2
public import SwiftUI

/// Presents the first failure in the explicitly supplied task priority order.
public enum Tasks {
    @MainActor
    public struct Failure: SwiftUI.View {
        private let title: Text?
        private let tasks: [StoreTaskID]
        public init(_ tasks: StoreTaskID...) { self.title = nil; self.tasks = tasks }
        public init(_ title: LocalizedStringKey, _ tasks: StoreTaskID...) { self.title = Text(title); self.tasks = tasks }
        public init(_ title: Text, _ tasks: StoreTaskID...) { self.title = title; self.tasks = tasks }

        public var body: some SwiftUI.View {
            if let error = tasks.lazy.compactMap(\.taskError).first {
                if let title { Section { Text(error.localizedDescription).foregroundStyle(.red) } header: { title } }
                else { Text(error.localizedDescription).foregroundStyle(.red) }
            }
        }
    }
}
