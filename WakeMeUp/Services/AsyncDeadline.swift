import Foundation

enum AsyncDeadlineError: Error, Equatable {
    case timedOut
}

enum AsyncDeadline {
    /// Runs work until it finishes or the deadline passes. A hung iCloud call becomes `.timedOut`.
    static func run<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AsyncDeadlineError.timedOut
            }
            do {
                guard let value = try await group.next() else { throw AsyncDeadlineError.timedOut }
                group.cancelAll()
                return value
            } catch is CancellationError {
                group.cancelAll()
                throw CancellationError()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}
