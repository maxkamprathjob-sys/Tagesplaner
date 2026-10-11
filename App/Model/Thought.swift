import Foundation
import SwiftData
import PlannerCore

/// Ordner für Gedanken (z. B. Arbeit, Freizeit, eigene Ordner).
@Model
final class ThoughtFolder {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "folder"
    /// Eigene Stichwörter, komma- oder zeilengetrennt.
    var keywordsText: String = ""
    /// Aus Korrekturen gelernte Gewichte (JSON [Wortstamm: Gewicht]).
    var learnedData: Data = Data()
    var sortOrder: Int = 0
    var isBuiltIn: Bool = false
    var createdAt: Date = Date()

    init(name: String, symbol: String, keywords: String = "", sortOrder: Int, isBuiltIn: Bool = false) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.keywordsText = keywords
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
    }

    var keywords: [String] {
        keywordsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var learned: [String: Double] {
        get { (try? JSONDecoder().decode([String: Double].self, from: learnedData)) ?? [:] }
        set {
            // Größe begrenzen: die schwächsten Einträge fallen weg.
            var dict = newValue.filter { abs($0.value) >= 0.1 }
            if dict.count > 400 {
                let keep = dict.sorted { abs($0.value) > abs($1.value) }.prefix(400)
                dict = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            }
            learnedData = (try? JSONEncoder().encode(dict)) ?? Data()
        }
    }

    var profile: ThoughtFolderProfile {
        ThoughtFolderProfile(id: id.uuidString, name: name, keywords: keywords, learned: learned, isCustom: !isBuiltIn)
    }
}

/// Ein festgehaltener Gedanke.
@Model
final class Thought {
    @Attribute(.unique) var id: UUID = UUID()
    var text: String = ""
    /// nil = Unsortiert
    var folderID: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// true = von der Sortierung zugeordnet (nicht vom Benutzer verschoben)
    var autoSorted: Bool = true
    /// Begriffe, an denen der Ordner erkannt wurde.
    var matchedText: String = ""

    init(text: String, folderID: UUID?, autoSorted: Bool, matched: [String], createdAt: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.folderID = folderID
        self.autoSorted = autoSorted
        self.matchedText = matched.joined(separator: ", ")
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

/// Ziel beim Einsortieren/Verschieben.
enum FolderTarget: Hashable {
    case unsorted
    case folder(UUID)

    var folderID: UUID? {
        if case .folder(let id) = self { return id }
        return nil
    }

    init(_ id: UUID?) {
        self = id.map { .folder($0) } ?? .unsorted
    }
}

enum Unsorted {
    static let name = "Unsortiert"
    static let symbol = "tray"
}
