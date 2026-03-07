import Foundation

actor ChangeCoalescer {
    private var pendingTask: Task<Void, Never>?
    private let delay: Duration = .milliseconds(500)

    func enqueue(save: @escaping @Sendable () async throws -> Void) {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            try? await save()
        }
    }

    /// Force any pending save to execute immediately
    func flush(save: @escaping @Sendable () async throws -> Void) {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await save()
        }
    }
}
