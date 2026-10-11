import Foundation
import SwiftData
import WidgetKit
import PlannerCore

/// Geschäftslogik für den Bereich "Gedanken".
/// Alle Änderungen laufen hierüber: speichern, lernen, Widgets aktualisieren.
@MainActor
final class ThoughtStore: ObservableObject {
    let context: ModelContext
    private let defaults: UserDefaults

    @Published private(set) var revision = 0
    @Published var errorMessage: String?

    /// In Tests aus (deterministisch, keine Systemdienste).
    var integrationsEnabled = true
    var semanticEnabled = true

    static let defaultFolders: [(name: String, symbol: String)] = [
        ("Arbeit", "briefcase"),
        ("Freizeit", "sparkles"),
        ("Freunde", "person.2"),
        ("Aufgaben", "checklist"),
        ("Haushalt", "house")
    ]

    init(context: ModelContext, defaults: UserDefaults = AppGroup.defaults) {
        self.context = context
        self.defaults = defaults
    }

    // MARK: - Lesen

    func folders() -> [ThoughtFolder] {
        let d = FetchDescriptor<ThoughtFolder>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        return (try? context.fetch(d)) ?? []
    }

    func folder(id: UUID?) -> ThoughtFolder? {
        guard let id else { return nil }
        return folders().first { $0.id == id }
    }

    func allThoughts() -> [Thought] {
        let d = FetchDescriptor<Thought>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func thought(id: UUID) -> Thought? {
        allThoughts().first { $0.id == id }
    }

    func thoughts(in target: FolderTarget) -> [Thought] {
        allThoughts().filter { $0.folderID == target.folderID }
    }

    func name(of target: FolderTarget) -> String {
        folder(id: target.folderID)?.name ?? Unsorted.name
    }

    func symbol(of target: FolderTarget) -> String {
        folder(id: target.folderID)?.symbol ?? Unsorted.symbol
    }

    // MARK: - Ordner anlegen (Erststart)

    func ensureDefaultFolders() {
        let key = "thoughtFoldersSeeded"
        guard !defaults.bool(forKey: key) else { return }
        if folders().isEmpty {
            for (i, f) in Self.defaultFolders.enumerated() {
                context.insert(ThoughtFolder(name: f.name, symbol: f.symbol, sortOrder: i, isBuiltIn: true))
            }
            save()
        }
        defaults.set(true, forKey: key)
    }

    // MARK: - Sortieren

    struct Prediction {
        var target: FolderTarget
        var matched: [String]
    }

    func classify(_ text: String) -> Prediction {
        var scorer: ThoughtClassifier.SemanticScorer? = nil
        if semanticEnabled && SemanticSimilarity.isAvailable {
            scorer = { SemanticSimilarity.best($0, $1) }
        }
        let classifier = ThoughtClassifier(semantic: scorer)
        let all = folders()
        let result = classifier.classify(text, folders: all.map(\.profile))
        let id = result.folderID.flatMap(UUID.init(uuidString:))
        return Prediction(target: FolderTarget(id), matched: result.matchedTerms)
    }

    struct AddResult: Identifiable {
        let id = UUID()
        var thoughtID: UUID
        var target: FolderTarget
        var matched: [String]
        var wasAutomatic: Bool
    }

    /// Speichert einen Gedanken. Ohne `target` wird automatisch einsortiert.
    @discardableResult
    func add(_ rawText: String, to target: FolderTarget? = nil) -> AddResult? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let prediction = classify(trimmed)
        let chosen = target ?? prediction.target
        var text = ThoughtClassifier.removingTags(from: trimmed)
        if text.isEmpty { text = trimmed }
        let thought = Thought(text: text, folderID: chosen.folderID, autoSorted: target == nil,
                              matched: target == nil ? prediction.matched : [])
        context.insert(thought)
        save()
        return AddResult(thoughtID: thought.id, target: chosen, matched: target == nil ? prediction.matched : [],
                         wasAutomatic: target == nil)
    }

    /// Verschiebt einen Gedanken und lernt daraus für künftige Sortierungen.
    func move(_ thought: Thought, to target: FolderTarget) {
        let old = thought.folderID
        let new = target.folderID
        guard old != new else { return }
        let keys = ThoughtClassifier.learningKeys(for: thought.text)
        if let f = folder(id: new) {
            var l = f.learned
            for k in keys { l[k] = min(4, l[k, default: 0] + 1.2) }
            f.learned = l
        }
        if thought.autoSorted, let f = folder(id: old) {
            var l = f.learned
            for k in keys { l[k] = max(-3, l[k, default: 0] - 0.6) }
            f.learned = l
        }
        thought.folderID = new
        thought.autoSorted = false
        thought.matchedText = ""
        thought.updatedAt = Date()
        save()
    }

    func updateText(_ thought: Thought, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != thought.text else { return }
        thought.text = trimmed
        thought.updatedAt = Date()
        // Unsortierte Gedanken nach dem Bearbeiten erneut einordnen.
        if thought.folderID == nil && thought.autoSorted {
            let p = classify(trimmed)
            thought.folderID = p.target.folderID
            thought.matchedText = p.matched.joined(separator: ", ")
            thought.autoSorted = true
        }
        save()
    }

    struct Deleted {
        var text: String
        var folderID: UUID?
        var createdAt: Date
    }

    @discardableResult
    func delete(_ thought: Thought) -> Deleted {
        let backup = Deleted(text: thought.text, folderID: thought.folderID, createdAt: thought.createdAt)
        context.delete(thought)
        save()
        return backup
    }

    func restore(_ d: Deleted) {
        let target = folder(id: d.folderID) == nil ? nil : d.folderID
        context.insert(Thought(text: d.text, folderID: target, autoSorted: false, matched: [], createdAt: d.createdAt))
        save()
    }

    // MARK: - Ordner verwalten

    /// Legt einen Ordner an und ordnet passende unsortierte Gedanken direkt ein.
    /// - Returns: Anzahl der neu eingeordneten Gedanken.
    @discardableResult
    func addFolder(name: String, symbol: String, keywords: String) -> (folder: ThoughtFolder, moved: Int) {
        let order = (folders().map(\.sortOrder).max() ?? -1) + 1
        let f = ThoughtFolder(name: name.trimmingCharacters(in: .whitespaces), symbol: symbol,
                              keywords: keywords, sortOrder: order)
        context.insert(f)
        save()
        return (f, sortUnsorted())
    }

    func updateFolder(_ f: ThoughtFolder, name: String, symbol: String, keywords: String) {
        f.name = name.trimmingCharacters(in: .whitespaces)
        f.symbol = symbol
        f.keywordsText = keywords
        save()
    }

    /// Löscht einen Ordner; seine Gedanken bleiben erhalten und werden "Unsortiert".
    func deleteFolder(_ f: ThoughtFolder) {
        for t in allThoughts() where t.folderID == f.id {
            t.folderID = nil
            t.autoSorted = true
        }
        context.delete(f)
        save()
    }

    func reorderFolders(from source: IndexSet, to destination: Int) {
        var list = folders()
        list.move(fromOffsets: source, toOffset: destination)
        for (i, f) in list.enumerated() { f.sortOrder = i }
        save()
    }

    func resetLearning(_ f: ThoughtFolder) {
        f.learned = [:]
        save()
    }

    /// Ordnet alle unsortierten Gedanken erneut ein (nur die, für die es jetzt eine sichere Zuordnung gibt).
    @discardableResult
    func sortUnsorted() -> Int {
        var moved = 0
        for t in allThoughts() where t.folderID == nil {
            let p = classify(t.text)
            if let id = p.target.folderID {
                t.folderID = id
                t.autoSorted = true
                t.matchedText = p.matched.joined(separator: ", ")
                moved += 1
            }
        }
        if moved > 0 { save() }
        return moved
    }

    // MARK: - Speichern & Widgets

    func save() {
        do {
            try context.save()
        } catch {
            errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
        revision += 1
        publish()
    }

    /// Neu zeichnen (z. B. nachdem Siri im Hintergrund etwas notiert hat).
    func refresh() {
        revision += 1
        publish()
    }

    func makeSnapshot() -> ThoughtsSnapshot {
        let folders = folders()
        let thoughts = allThoughts()
        var info: [ThoughtsSnapshot.Folder] = folders.map { f in
            ThoughtsSnapshot.Folder(id: f.id.uuidString, name: f.name, symbol: f.symbol,
                                    count: thoughts.filter { $0.folderID == f.id }.count)
        }
        let unsortedCount = thoughts.filter { $0.folderID == nil }.count
        info.append(ThoughtsSnapshot.Folder(id: ThoughtsSnapshot.unsortedID, name: Unsorted.name,
                                            symbol: Unsorted.symbol, count: unsortedCount))
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let items = thoughts.prefix(60).map { t -> ThoughtsSnapshot.Item in
            let f = t.folderID.flatMap { byID[$0] }
            return ThoughtsSnapshot.Item(id: t.id.uuidString, text: t.text,
                                         folderID: f?.id.uuidString ?? ThoughtsSnapshot.unsortedID,
                                         folderName: f?.name ?? Unsorted.name,
                                         symbol: f?.symbol ?? Unsorted.symbol,
                                         createdAt: t.createdAt)
        }
        return ThoughtsSnapshot(generatedAt: Date(), folders: info, items: Array(items))
    }

    func publish() {
        guard integrationsEnabled else { return }
        do {
            try ThoughtsSnapshotStore.write(makeSnapshot())
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widgets sind optional – die App funktioniert ohne sie weiter.
        }
    }
}
