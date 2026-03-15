import Foundation

actor ChangeCoalescer {
    private var pendingTask: Task<Void, Never>?
    private let delay: Duration = .milliseconds(500)
    private var onError: (@Sendable (Error) -> Void)?

    func setErrorHandler(_ handler: @escaping @Sendable (Error) -> Void) {
        self.onError = handler
    }

    func enqueue(save: @escaping @Sendable () async throws -> Void) {
        pendingTask?.cancel()
        pendingTask = Task {
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
        pendingTask?.cancel()
        pendingTask = Task {
            do {
                try await save()
            } catch {
                onError?(error)
            }
        }
    }
}
