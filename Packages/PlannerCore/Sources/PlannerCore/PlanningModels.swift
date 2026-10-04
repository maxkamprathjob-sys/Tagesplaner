import Foundation

/// Priorität einer Aufgabe.
public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable, Identifiable {
    case low = 0
    case normal = 1
    case high = 2
    case veryHigh = 3

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .low: return "Niedrig"
        case .normal: return "Normal"
        case .high: return "Hoch"
        case .veryHigh: return "Sehr hoch"
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Ein belegter Zeitraum, wie ihn die Planungslogik sieht.
/// Wird aus App-Einträgen und (optional) Apple-Kalenderterminen erzeugt.
public struct ScheduleEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case fixed      // fester Termin (Uni, Arzt …)
        case flexible   // eingeplante Aufgabe
        case external   // Apple-Kalender (nur lesend)
        case sleep      // Schlafblock
    }

    public var id: String
    public var title: String
    public var interval: DateInterval
    public var kind: Kind

    public init(id: String, title: String, interval: DateInterval, kind: Kind) {
        self.id = id
        self.title = title
        self.interval = interval
        self.kind = kind
    }
}

/// Eine Aufgabe, für die ein Zeitraum gesucht wird.
public struct TaskRequest: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var durationMinutes: Int
    public var priority: Priority
    public var deadline: Date?

    public init(id: String, title: String, durationMinutes: Int,
                priority: Priority = .normal, deadline: Date? = nil) {
        self.id = id
        self.title = title
        self.durationMinutes = max(5, durationMinutes)
        self.priority = priority
        self.deadline = deadline
    }
}

/// Persönliche Planungseinstellungen.
public struct PlannerSettings: Codable, Hashable, Sendable {
    /// Ab wann geplant werden darf (Aufstehen).
    public var wakeTime: TimeOfDay
    /// Schlafenszeit. Liegt sie vor der Aufstehzeit (z. B. 00:30), ist der Folgetag gemeint.
    public var bedtime: TimeOfDay
    /// Pause, die vor und nach festen Blöcken frei gehalten wird.
    public var bufferMinutes: Int
    /// Kleinste Lücke, die als "frei" gilt.
    public var minimumSlotMinutes: Int
    /// Raster für Vorschläge.
    public var gridMinutes: Int

    public init(wakeTime: TimeOfDay = TimeOfDay(hour: 7),
                bedtime: TimeOfDay = TimeOfDay(hour: 21),
                bufferMinutes: Int = 10,
                minimumSlotMinutes: Int = 15,
                gridMinutes: Int = 5) {
        self.wakeTime = wakeTime
        self.bedtime = bedtime
        self.bufferMinutes = max(0, bufferMinutes)
        self.minimumSlotMinutes = max(5, minimumSlotMinutes)
        self.gridMinutes = max(1, gridMinutes)
    }

    public static let standard = PlannerSettings()
}

/// Zwei sich überschneidende Einträge.
public struct Conflict: Hashable, Sendable {
    public var first: ScheduleEntry
    public var second: ScheduleEntry
    public var overlap: DateInterval

    public var message: String {
        "„\(first.title)“ und „\(second.title)“ überschneiden sich (\(DurationText.exact(DayMath.minutes(overlap))))."
    }
}

public enum ConflictDetector {

    /// Findet alle paarweisen Überschneidungen. Nichts wird verändert –
    /// die App zeigt Konflikte nur an.
    public static func conflicts(in entries: [ScheduleEntry]) -> [Conflict] {
        let sorted = entries
            .filter { $0.interval.duration > 0 }
            .sorted { ($0.interval.start, $0.id) < ($1.interval.start, $1.id) }
        var result: [Conflict] = []
        for i in 0..<sorted.count {
            var j = i + 1
            while j < sorted.count && sorted[j].interval.start < sorted[i].interval.end {
                if let overlap = DayMath.intersection(sorted[i].interval, sorted[j].interval) {
                    result.append(Conflict(first: sorted[i], second: sorted[j], overlap: overlap))
                }
                j += 1
            }
        }
        return result
    }

    public static func conflictingIDs(in entries: [ScheduleEntry]) -> Set<String> {
        var ids = Set<String>()
        for c in conflicts(in: entries) {
            ids.insert(c.first.id)
            ids.insert(c.second.id)
        }
        return ids
    }

    /// Prüft, ob ein neuer Zeitraum mit bestehenden Einträgen kollidiert.
    public static func collisions(of interval: DateInterval, ignoring id: String? = nil,
                                  in entries: [ScheduleEntry]) -> [ScheduleEntry] {
        entries.filter { $0.id != id && DayMath.overlaps($0.interval, interval) }
    }
}
