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
        let debounceDelay = delay
        pendingTasks[date] = Task { [weak self] in
            try? await Task.sleep(for: debounceDelay)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.executePendingSave(for: date)
        }
    }

    /// Execute and clear the pending save for a date, if it still exists.
    private func executePendingSave(for date: Date) async {
        guard let save = pendingSaves.removeValue(forKey: date) else { return }
        pendingTasks.removeValue(forKey: date)
        do {
            try await save()
        } catch {
            onError?(error)
        }
    }

    /// Force all pending saves to execute immediately, bypassing debounce delays.
    /// Cancels the debounced tasks first, then runs each save directly.
    func flush() async {
        // Cancel all debounced tasks so they don't fire after flush
        for (_, task) in pendingTasks {
            task.cancel()
        }
        pendingTasks.removeAll()

        // Take the pending saves and execute them
        let pending = pendingSaves
        pendingSaves.removeAll()
        for (_, save) in pending {
            do {
                try await save()
            } catch {
                onError?(error)
            }
        }
    }
}
