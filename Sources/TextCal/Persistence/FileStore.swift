import Foundation

/// Per-day file storage for journal text.
/// Events are stored in EventKit; this only handles freeform text.
///
/// Directory structure:
///   Documents/textcal/schema.json            — schema version marker
///   Documents/textcal/journal/2026-03-08.txt — one file per day, plain text
///
/// Schema versioning:
/// The `schema.json` file records the on-disk format version so future
/// releases can detect old layouts and migrate forward. It's written on
/// first save and read on load. A missing file is treated as the oldest
/// known version (legacy migration path). Per-day files are kept as plain
/// text (no embedded header) so users can open/edit them in the Files app
/// without format concerns.
actor FileStore {
    /// Current on-disk schema version. Bump when the file layout changes.
    /// History:
    ///   1 — per-day plain-text .txt files under textcal/journal/
    static let currentSchemaVersion = 1

    private let rootDir: URL
    private let journalDir: URL
    private let legacyFileURL: URL
    private let schemaFileURL: URL

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(baseURL: URL) {
        self.rootDir = baseURL.appendingPathComponent("textcal", isDirectory: true)
        self.journalDir = rootDir.appendingPathComponent("journal", isDirectory: true)
        self.legacyFileURL = baseURL.appendingPathComponent("calendar.md")
        self.schemaFileURL = rootDir.appendingPathComponent("schema.json")
    }

    /// Local Documents directory. Always available.
    static func localBaseURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// iCloud Drive base URL for the app's ubiquity container, or nil if
    /// the user is not signed into iCloud or the container isn't provisioned.
    /// This call can block briefly on first use; call off the main thread.
    static func cloudBaseURL() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return container.appendingPathComponent("Documents", isDirectory: true)
    }

    /// Seed the `textcal/` tree at `destination` from `source`, but only if
    /// the destination is empty (no journal files and no templates). Returns
    /// the number of files copied. This is a one-shot seed, not a continuous
    /// sync — once both sides have data, each side is considered authoritative
    /// for its own storage mode. Used to bootstrap the user's data into the
    /// new base when they first toggle iCloud sync on or off.
    @discardableResult
    static func migrateTextCalTree(from source: URL, to destination: URL) throws -> Int {
        let fm = FileManager.default
        let sourceRoot = source.appendingPathComponent("textcal", isDirectory: true)
        guard fm.fileExists(atPath: sourceRoot.path) else { return 0 }

        let destRoot = destination.appendingPathComponent("textcal", isDirectory: true)
        // Only seed when destination has no journal files and no templates.
        // Anything more complex (bidirectional merge) is out of scope here —
        // the user keeps files on both sides once both are populated.
        let destJournal = destRoot.appendingPathComponent("journal", isDirectory: true)
        let destTemplates = destRoot.appendingPathComponent("templates.json")
        let journalFiles = (try? fm.contentsOfDirectory(at: destJournal, includingPropertiesForKeys: nil)) ?? []
        let hasData = !journalFiles.isEmpty || fm.fileExists(atPath: destTemplates.path)
        if hasData { return 0 }

        try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)

        var copied = 0
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let enumerator = fm.enumerator(at: sourceRoot, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        let sourcePrefix = sourceRoot.path
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: keys))?.isDirectory ?? false
            var relative = String(fileURL.path.dropFirst(sourcePrefix.count))
            while relative.hasPrefix("/") { relative.removeFirst() }
            guard !relative.isEmpty else { continue }
            let destURL = destRoot.appendingPathComponent(relative)
            if isDir {
                try? fm.createDirectory(at: destURL, withIntermediateDirectories: true)
            } else if !fm.fileExists(atPath: destURL.path) {
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: fileURL, to: destURL)
                copied += 1
            }
        }
        return copied
    }

    /// Ensure the journal directory exists
    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        writeSchemaIfNeeded()
    }

    // MARK: - Schema Version

    /// On-disk schema envelope for textcal/schema.json.
    /// Unknown fields are preserved by decoding permissively; future fields
    /// can be added without breaking older builds.
    private struct SchemaFile: Codable {
        var version: Int
        var format: String
        var writtenBy: String?
    }

    /// Read the on-disk schema version, or nil if no schema file exists.
    /// Callers use this to decide whether to run a migration.
    func readSchemaVersion() -> Int? {
        guard FileManager.default.fileExists(atPath: schemaFileURL.path),
              let data = try? Data(contentsOf: schemaFileURL),
              let schema = try? JSONDecoder().decode(SchemaFile.self, from: data) else {
            return nil
        }
        return schema.version
    }

    /// Write the current schema marker if missing or out-of-date. Non-fatal on failure.
    private func writeSchemaIfNeeded() {
        let existing = readSchemaVersion()
        if existing == Self.currentSchemaVersion { return }
        let schema = SchemaFile(
            version: Self.currentSchemaVersion,
            format: "per-day-txt",
            writtenBy: "TextCal"
        )
        guard let data = try? JSONEncoder().encode(schema) else { return }
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        try? data.write(to: schemaFileURL, options: .atomic)
    }

    /// Load journal text for a specific date via a coordinated read so
    /// concurrent writes (e.g., iCloud syncing the file in from another
    /// device) don't race with us. If unresolved `NSFileVersion` conflict
    /// versions exist, they're merged inline first under a coordinated
    /// write so the user sees both sides of the conflict in the text.
    func loadJournal(for date: Date) async throws -> String {
        let url = fileURL(for: date)
        // Pull the file down from iCloud if it's only a placeholder. Safe
        // no-op when the file lives locally.
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Merge any pending iCloud conflicts before reading so we return a
        // single coherent string. Separate step because conflict resolution
        // requires writing access — you can't mix read and write options
        // inside one `coordinate(readingItemAt:...)` block.
        try Self.mergeConflictsIfAny(at: url)

        return try Self.coordinatedRead(at: url)
    }

    /// Coordinated read of `url` via `NSFileCoordinator`. Returns "" when
    /// the file doesn't exist. Coordination blocks until the file system
    /// daemon grants exclusive read access — prevents iCloud sync from
    /// shoving a half-written file at us mid-read.
    private static func coordinatedRead(at url: URL) throws -> String {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: String = ""
        var thrownError: Error?
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { coordinatedURL in
            guard FileManager.default.fileExists(atPath: coordinatedURL.path) else { return }
            do {
                result = try String(contentsOf: coordinatedURL, encoding: .utf8)
            } catch {
                thrownError = error
            }
        }
        if let coordError { throw coordError }
        if let thrownError { throw thrownError }
        return result
    }

    /// If `NSFileVersion.unresolvedConflictVersionsOfItem` reports conflicts
    /// for `url`, merge their contents inline under a visible separator via
    /// a coordinated write. No-op when there are no conflicts (common case,
    /// returns immediately without acquiring coordination).
    private static func mergeConflictsIfAny(at url: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return }

        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var thrownError: Error?
        coordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &coordError) { coordinatedURL in
            do {
                let current = (try? String(contentsOf: coordinatedURL, encoding: .utf8)) ?? ""
                var merged = current
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short

                for version in conflicts {
                    let content = (try? String(contentsOf: version.url, encoding: .utf8)) ?? ""
                    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedContent.isEmpty || content == current {
                        version.isResolved = true
                        continue
                    }
                    let device = version.localizedNameOfSavingComputer ?? "another device"
                    let when = version.modificationDate.map { formatter.string(from: $0) } ?? ""
                    let header = "\n\n--- conflict from \(device) at \(when) ---\n\n"
                    merged += header + content
                    version.isResolved = true
                }

                if merged != current {
                    try merged.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                }
                try? NSFileVersion.removeOtherVersionsOfItem(at: coordinatedURL)
            } catch {
                thrownError = error
            }
        }
        if let coordError { throw coordError }
        if let thrownError { throw thrownError }
    }

    /// Save journal text for `date` under a coordinated write so other
    /// readers (iCloud daemon, another device syncing in) see a complete
    /// file rather than a half-flushed one.
    func saveJournal(_ text: String, for date: Date) async throws {
        try ensureDirectory()
        let url = fileURL(for: date)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var thrownError: Error?
        if trimmed.isEmpty {
            coordinator.coordinate(writingItemAt: url, options: [.forDeleting], error: &coordError) { coordinatedURL in
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    do {
                        try FileManager.default.removeItem(at: coordinatedURL)
                    } catch {
                        thrownError = error
                    }
                }
            }
        } else {
            let toWrite = text.trimmingCharacters(in: .newlines)
            coordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &coordError) { coordinatedURL in
                do {
                    try toWrite.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                } catch {
                    thrownError = error
                }
            }
        }
        if let coordError { throw coordError }
        if let thrownError { throw thrownError }
    }

    /// Load all journal entries for initial load. Uses a single batched
    /// coordination via `prepare(forReadingItemsAt:...)` so the file system
    /// daemon grants access to all day files in one round-trip — faster
    /// than coordinating each file individually on iCloud-backed stores.
    func loadAllJournals() async throws -> [Date: String] {
        try ensureDirectory()
        var results: [Date: String] = [:]

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: nil) else {
            return results
        }
        let txtFiles = files.filter { $0.pathExtension == "txt" }
        guard !txtFiles.isEmpty else { return results }

        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.prepare(forReadingItemsAt: txtFiles, options: [.withoutChanges], writingItemsAt: [], options: [], error: &coordError) { completionHandler in
            defer { completionHandler() }
            for file in txtFiles {
                let name = file.deletingPathExtension().lastPathComponent
                guard let date = Self.dateFormatter.date(from: name) else { continue }
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results[DateFormatting.normalizeToDay(date)] = content
                }
            }
        }
        if let coordError { throw coordError }
        return results
    }

    /// Check if legacy single-file format exists (for migration)
    func hasLegacyFile() -> Bool {
        FileManager.default.fileExists(atPath: legacyFileURL.path)
    }

    /// Load legacy single-file content for migration
    func loadLegacy() async throws -> String {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return ""
        }
        return try String(contentsOf: legacyFileURL, encoding: .utf8)
    }

    /// Remove legacy file after successful migration
    func removeLegacyFile() throws {
        if FileManager.default.fileExists(atPath: legacyFileURL.path) {
            try FileManager.default.removeItem(at: legacyFileURL)
        }
    }

    private func fileURL(for date: Date) -> URL {
        let name = Self.dateFormatter.string(from: DateFormatting.normalizeToDay(date))
        return journalDir.appendingPathComponent("\(name).txt")
    }
}
