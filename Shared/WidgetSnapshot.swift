import Foundation

/// Kompakte, schreibgeschützte Kopie der wichtigsten Tagesdaten für Widgets.
/// Die App schreibt sie nach jeder Änderung; Widgets lesen sie nur.
/// (Widgets greifen bewusst nicht direkt auf die Datenbank zu – so kann ein
/// Widget-Fehler niemals Daten beschädigen.)
struct WidgetSnapshot: Codable, Hashable {

    struct Item: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var symbol: String
        var isTask: Bool
        var isDone: Bool
        var isExternal: Bool
        var isSleep: Bool
    }

    struct OpenTask: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var deadline: Date?
        var priority: Int
        var minutes: Int?
    }

    var generatedAt: Date
    /// Zeitblöcke von gestern bis in drei Tagen.
    var items: [Item]
    /// Offene Aufgaben je Tag, Schlüssel "yyyy-MM-dd".
    var openTasks: [String: [OpenTask]]

    static let empty = WidgetSnapshot(generatedAt: .distantPast, items: [], openTasks: [:])

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Blöcke, die den Tag berühren, chronologisch.
    func items(on day: Date, calendar: Calendar = .current) -> [Item] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return items.filter { $0.start < end && $0.end > start }.sorted { $0.start < $1.start }
    }

    /// Laufender Block (Schlaf nur, wenn sonst nichts läuft).
    func current(at now: Date) -> Item? {
        let running = items.filter { $0.start <= now && $0.end > now }.sorted { $0.start > $1.start }
        return running.first(where: { !$0.isSleep }) ?? running.first
    }

    /// Kommende Blöcke ab jetzt.
    func upcoming(after now: Date, limit: Int) -> [Item] {
        Array(items.filter { $0.start > now }.sorted { $0.start < $1.start }.prefix(limit))
    }

    /// Relevante Blöcke für "HEUTE": laufende und kommende des Tages.
    func remainingToday(at now: Date, calendar: Calendar = .current) -> [Item] {
        items(on: now, calendar: calendar).filter { $0.end > now }
    }

    func openTasks(on day: Date, calendar: Calendar = .current) -> [OpenTask] {
        openTasks[WidgetSnapshot.dayKey(day, calendar: calendar)] ?? []
    }

    /// Zeitpunkte, an denen sich die Widget-Anzeige ändern muss.
    func changeDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        var dates = Set<Date>()
        for item in items {
            if item.start > now { dates.insert(item.start) }
            if item.end > now { dates.insert(item.end) }
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        if let t = tomorrow { dates.insert(t) }
        return dates.sorted()
    }
}

/// Liest und schreibt den Snapshot als JSON im App-Group-Ordner.
enum SnapshotStore {
    private static var url: URL {
        AppGroup.storageDirectory.appendingPathComponent("widget-snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    /// Fehlertolerant: liefert nil statt abzustürzen.
    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
