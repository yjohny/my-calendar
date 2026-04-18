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

    /// Load journal text for a specific date
    func loadJournal(for date: Date) async throws -> String {
        let url = fileURL(for: date)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Save journal text for a specific date
    func saveJournal(_ text: String, for date: Date) async throws {
        try ensureDirectory()
        let url = fileURL(for: date)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } else {
            // Write the original text (preserving user's trailing newlines within content)
            // but ensure we don't write purely whitespace files
            try text.trimmingCharacters(in: .newlines).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Load all journal entries (for initial load)
    func loadAllJournals() async throws -> [Date: String] {
        try ensureDirectory()
        var results: [Date: String] = [:]

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: nil) else {
            return results
        }

        for file in files where file.pathExtension == "txt" {
            let name = file.deletingPathExtension().lastPathComponent
            if let date = Self.dateFormatter.date(from: name) {
                let content = try String(contentsOf: file, encoding: .utf8)
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results[DateFormatting.normalizeToDay(date)] = content
                }
            }
        }

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
