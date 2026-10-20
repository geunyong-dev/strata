import Foundation

struct CleanupHistoryStore: Sendable {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = applicationSupport
                .appending(path: "Strata", directoryHint: .isDirectory)
                .appending(path: "cleanup-history.json")
        }
    }

    func load() -> [CleanupRunSummary] {
        (try? loadChecked()) ?? []
    }

    func loadChecked() throws -> [CleanupRunSummary] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Array(try decoder.decode([CleanupRunSummary].self, from: data)
            .sorted { $0.finishedAt > $1.finishedAt }.prefix(50))
    }

    func save(_ history: [CleanupRunSummary]) throws {
        // Do not overwrite an unreadable or corrupt existing history silently.
        _ = try loadChecked()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Array(history.sorted { $0.finishedAt > $1.finishedAt }.prefix(50)))
            .write(to: fileURL, options: .atomic)
    }
}
