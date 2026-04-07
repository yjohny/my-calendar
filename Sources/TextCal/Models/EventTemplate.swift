import Foundation

/// A reusable text snippet that can be inserted into a day's text.
struct EventTemplate: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var text: String

    init(id: UUID = UUID(), name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
    }
}

/// Versioned envelope for templates.json. Wrapping the array in a struct
/// with an explicit `version` field lets future releases change the template
/// shape without breaking on old files — decoders can branch on version.
///
/// Version history:
///   1 — `[EventTemplate]` stored as a bare array (unversioned, pre-1.0)
///   2 — `TemplateFile { version, templates }` envelope
private struct TemplateFile: Codable {
    var version: Int
    var templates: [EventTemplate]
}

/// Persists event templates as a JSON file in the app's documents directory.
actor TemplateStore {
    /// Current on-disk template file version. Bump when the schema changes.
    static let currentVersion = 2

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("textcal/templates.json")
    }

    func load() -> [EventTemplate] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        // Try the current versioned envelope first
        if let file = try? JSONDecoder().decode(TemplateFile.self, from: data) {
            return file.templates
        }
        // Fall back to legacy bare-array format (version 1)
        if let templates = try? JSONDecoder().decode([EventTemplate].self, from: data) {
            return templates
        }
        return []
    }

    func save(_ templates: [EventTemplate]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = TemplateFile(version: Self.currentVersion, templates: templates)
        let data = try JSONEncoder().encode(file)
        try data.write(to: fileURL, options: .atomic)
    }
}
