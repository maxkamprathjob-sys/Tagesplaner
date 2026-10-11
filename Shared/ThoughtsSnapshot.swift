import Foundation

/// Schreibgeschützte Kopie der Gedanken für die Widgets (eigene Datei,
/// unabhängig vom Tagesplan-Snapshot).
struct ThoughtsSnapshot: Codable, Hashable {
    struct Folder: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var symbol: String
        var count: Int
    }

    struct Item: Codable, Hashable, Identifiable {
        var id: String
        var text: String
        var folderID: String
        var folderName: String
        var symbol: String
        var createdAt: Date
    }

    static let unsortedID = "unsorted"

    var generatedAt: Date
    var folders: [Folder]
    /// Neueste zuerst.
    var items: [Item]

    func items(inFolder id: String?) -> [Item] {
        guard let id else { return items }
        return items.filter { $0.folderID == id }
    }

    func folder(id: String?) -> Folder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }
}

enum ThoughtsSnapshotStore {
    private static var url: URL {
        AppGroup.storageDirectory.appendingPathComponent("thoughts-snapshot.json")
    }

    static func write(_ snapshot: ThoughtsSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: url, options: [.atomic])
    }

    static func read() -> ThoughtsSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ThoughtsSnapshot.self, from: data)
    }
}
