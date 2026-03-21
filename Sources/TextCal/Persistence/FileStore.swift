import Foundation

/// Per-day file storage for journal text.
/// Events are stored in EventKit; this only handles freeform text.
///
/// Directory structure:
///   Documents/textcal/journal/2026-03-08.txt
actor FileStore {
    private let journalDir: URL
    private let legacyFileURL: URL

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.journalDir = docs.appendingPathComponent("textcal/journal", isDirectory: true)
        self.legacyFileURL = docs.appendingPathComponent("calendar.md")
    }

    /// Ensure the journal directory exists
    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
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
