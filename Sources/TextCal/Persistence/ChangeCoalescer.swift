import Foundation

actor ChangeCoalescer {
    private var pendingTasks: [Date: Task<Void, Never>] = [:]
    private let delay: Duration = .milliseconds(500)
    private var onError: (@Sendable (Error) -> Void)?

    func setErrorHandler(_ handler: @escaping @Sendable (Error) -> Void) {
        self.onError = handler
    }

    func enqueue(for date: Date, save: @escaping @Sendable () async throws -> Void) {
        pendingTasks[date]?.cancel()
        pendingTasks[date] = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            do {
                try await save()
            } catch {
                onError?(error)
            }
        }
    }

    /// Force any pending save to execute immediately
    func flush(save: @escaping @Sendable () async throws -> Void) {
        for (date, task) in pendingTasks {
            task.cancel()
            pendingTasks.removeValue(forKey: date)
        }
        pendingTasks[Date.distantPast] = Task {
            do {
                try await save()
            } catch {
                onError?(error)
            }
        }
    }
}
