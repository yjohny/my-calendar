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

/// Persists event templates as a JSON file in the app's documents directory.
actor TemplateStore {
    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("textcal/templates.json")
    }

    func load() -> [EventTemplate] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let templates = try? JSONDecoder().decode([EventTemplate].self, from: data) else {
            return []
        }
        return templates
    }

    func save(_ templates: [EventTemplate]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(templates)
        try data.write(to: fileURL, options: .atomic)
    }
}
