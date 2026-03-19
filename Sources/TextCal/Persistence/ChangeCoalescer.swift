import Foundation

actor ChangeCoalescer {
    private var pendingTasks: [Date: Task<Void, Never>] = [:]
    private var pendingSaves: [Date: @Sendable () async throws -> Void] = [:]
    private let delay: Duration = .milliseconds(500)
    private var onError: (@Sendable (Error) -> Void)?

    func setErrorHandler(_ handler: @escaping @Sendable (Error) -> Void) {
        self.onError = handler
    }

    func enqueue(for date: Date, save: @escaping @Sendable () async throws -> Void) {
        pendingTasks[date]?.cancel()
        pendingSaves[date] = save
        pendingTasks[date] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.clearPendingSave(for: date)
            do {
                try await save()
            } catch {
                await self.reportError(error)
            }
        }
    }

    private func clearPendingSave(for date: Date) {
        pendingSaves.removeValue(forKey: date)
    }

    private func reportError(_ error: Error) {
        onError?(error)
    }

    /// Force all pending saves to execute immediately, bypassing debounce delays.
    /// Collects the save closures from pending tasks, cancels the debounced tasks,
    /// and runs each save directly.
    func flush() async {
        let pending = pendingSaves
        pendingSaves.removeAll()
        for (date, task) in pendingTasks {
            task.cancel()
            pendingTasks.removeValue(forKey: date)
        }
        for (_, save) in pending {
            do {
                try await save()
            } catch {
                onError?(error)
            }
        }
    }
}
