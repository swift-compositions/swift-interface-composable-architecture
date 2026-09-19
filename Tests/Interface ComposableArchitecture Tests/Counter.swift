import CasePaths
import Interface_ComposableArchitecture
import Operation
import Interface_Macro
import Synchronization

// A counter whose reads can also be observed: the fixture every bridge test runs against.
@Interface
struct Counter: Counter.Interface {
    enum Failure: Swift.Error, Equatable {
        case refused
    }

    protocol Interface {
        func increment(by amount: Int) async throws(Failure)
        func observe(from start: Int) -> AsyncThrowingStream<Int, any Swift.Error>
        func read() async -> Int
    }
}

final class Ledger: Sendable {
    private let storage = Mutex<[String]>([])

    var entries: [String] { storage.withLock { $0 } }

    func record(_ entry: String) { storage.withLock { $0.append(entry) } }
}

extension Counter.Call: CasePathable {}
