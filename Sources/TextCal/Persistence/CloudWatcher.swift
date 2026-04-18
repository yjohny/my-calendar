import Foundation

/// Watches the user's iCloud ubiquity container for changes to per-day
/// journal files and surfaces the affected dates via callbacks. Only
/// meaningful when the user has opted into iCloud sync.
///
/// Lifecycle:
///   - `start()` begins an `NSMetadataQuery` scoped to the ubiquity
///     documents scope. The initial gather is suppressed (we only react
///     to changes *after* the baseline is established — the existing
///     `loadAllJournals()` path already handles the initial read).
///   - `stop()` cancels the query and removes observers.
///
/// Callbacks fire on the main actor:
///   - `onChange` is called with the set of dates whose files were
///     added, modified, or removed on another device.
///   - `onStatusChange` toggles when the query is actively gathering,
///     so the UI can show a cloud spinner while changes stream in.
@MainActor
final class CloudWatcher {
    private let query = NSMetadataQuery()
    private let dateFormatter: DateFormatter
    private var observers: [NSObjectProtocol] = []
    private var hasFinishedInitialGather = false

    /// Fired with dates whose journal files changed on another device.
    var onChange: ((Set<Date>) -> Void)?

    /// Fired with `true` while the query is gathering, `false` when it settles.
    var onStatusChange: ((Bool) -> Void)?

    init() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter = f
    }

    deinit {
        // NotificationCenter's block-based observers retain their blocks with
        // a weak `self` capture, so the observer entries are harmless once
        // self deallocates. NSMetadataQuery is safe to leave — its retain
        // cycle is broken by self going away.
    }

    func start() {
        guard !query.isStarted else { return }

        // Match any .txt file in the ubiquity documents scope; we filter to
        // journal files by URL inspection when results arrive (the predicate
        // syntax for path-containment is unreliable across OS versions).
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*.txt")

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidStartGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onStatusChange?(true) }
        })
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.hasFinishedInitialGather = true
                self.onStatusChange?(false)
            }
        })
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] note in
            let userInfo = note.userInfo
            Task { @MainActor in
                self?.handleUpdate(userInfo: userInfo)
            }
        })

        query.start()
    }

    func stop() {
        query.stop()
        let toRemove = observers
        for observer in toRemove {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        hasFinishedInitialGather = false
    }

    private func handleUpdate(userInfo: [AnyHashable: Any]?) {
        guard hasFinishedInitialGather else { return }
        // Pause further updates while we process this batch — NSMetadataQuery
        // may otherwise interleave notifications while we enumerate items.
        query.disableUpdates()
        defer { query.enableUpdates() }

        let added = userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
        let changed = userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? []
        let removed = userInfo?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem] ?? []

        var dates: Set<Date> = []
        for item in (added + changed + removed) {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            // Only react to files under textcal/journal/.
            let parent = url.deletingLastPathComponent().lastPathComponent
            guard parent == "journal" else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            if let date = dateFormatter.date(from: name) {
                dates.insert(DateFormatting.normalizeToDay(date))
            }
        }

        guard !dates.isEmpty else { return }
        onChange?(dates)
    }
}
