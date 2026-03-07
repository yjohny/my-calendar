import Foundation

actor FileStore {
    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("calendar.md")
    }

    func load() async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ""
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func save(_ content: String) async throws {
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
