import AppIntents
import Foundation
import SwiftData
import PlannerCore

// Siri & Kurzbefehle. Alles läuft lokal im App-Prozess auf denselben Daten.

@MainActor
private func makeStore() -> PlanStore {
    let store = PlanStore(context: Persistence.shared.mainContext,
                          settings: SettingsStore(),
                          calendarService: CalendarService())
    return store
}

/// "Was steht heute an?"
struct TodayOverviewIntent: AppIntent {
    static var title: LocalizedStringResource = "Was steht heute an?"
    static var description = IntentDescription("Liest deinen heutigen Tagesplan und offene Aufgaben vor.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = makeStore()
        let now = Date()
        let blocks = store.timedItems(on: now).filter { ($0.end ?? now) > now && !$0.isSleep }
        let open = store.tasks(on: now).filter { !$0.isDone && !$0.isScheduled }

        var lines: [String] = []
        if blocks.isEmpty {
            lines.append("Heute stehen keine weiteren Termine an.")
        } else {
            lines.append("Heute: " + blocks.prefix(6).map { item in
                "\(Fmt.time(item.start ?? now)) \(item.title)"
            }.joined(separator: ", ") + ".")
        }
        if !open.isEmpty {
            lines.append(open.count == 1 ? "Außerdem 1 offene Aufgabe: \(open[0].title)."
                                         : "Außerdem \(open.count) offene Aufgaben.")
        }
        lines.append(store.dayLoad(on: now).headline)
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: " ")))
    }
}

/// "Was ist mein nächster Termin?"
struct NextEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Nächster Termin"
    static var description = IntentDescription("Nennt den nächsten Block in deinem Tagesplan.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = makeStore()
        let now = Date()
        let upcoming = store.allItems()
            .compactMap { item -> (PlanItem, DateInterval)? in
                guard let iv = item.interval, iv.start > now, !item.isDone else { return nil }
                return (item, iv)
            }
            .sorted { $0.1.start < $1.1.start }
        guard let first = upcoming.first else {
            return .result(dialog: "In deinem Tagesplan steht nichts mehr an.")
        }
        let item = first.0
        let iv = first.1
        let day = Fmt.relativeDayName(iv.start) ?? Fmt.shortDay(iv.start)
        return .result(dialog: IntentDialog(stringLiteral: "\(item.title), \(day) um \(Fmt.time(iv.start)) bis \(Fmt.time(iv.end))."))
    }
}

/// "Plane zwei Stunden Lernen ein."
/// Legt die Aufgabe an und sucht einen freien Zeitraum. Eingeplant wird erst nach
/// Bestätigung in der App – genau wie bei der normalen Eingabe.
struct PlanTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Aufgabe einplanen"
    static var description = IntentDescription("Legt eine Aufgabe an und schlägt eine freie Zeit vor.")
    static var openAppWhenRun = true

    @Parameter(title: "Was?", requestValueDialog: "Was möchtest du einplanen?")
    var text: String

    @Parameter(title: "Dauer in Minuten", default: 60)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$text) für \(\.$minutes) Minuten einplanen")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = makeStore()
        var parsed = NaturalLanguageParser(calendar: store.calendar).parse(text, now: Date())
        if parsed.durationMinutes == nil { parsed.durationMinutes = max(5, minutes) }
        let result = store.create(from: parsed, selectedDay: Date(), asTask: true)
        AppGroup.defaults.set(result.item.id.uuidString, forKey: PendingIntent.key)

        let day = result.item.day
        let suggestion = store.suggestion(for: result.item, on: day, within: result.window)
        switch suggestion {
        case .suggestion(let s):
            return .result(dialog: IntentDialog(stringLiteral:
                "„\(result.item.title)“ ist angelegt. Vorschlag: \(Fmt.range(s.interval.start, s.interval.end)). Bestätige ihn in der App."))
        case .noFit:
            return .result(dialog: IntentDialog(stringLiteral:
                "„\(result.item.title)“ ist angelegt, aber heute ist kein passender Zeitraum frei. In der App siehst du die Optionen."))
        }
    }
}

struct PlannerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TodayOverviewIntent(),
                    phrases: ["Was steht heute an in \(.applicationName)",
                              "Mein Tag in \(.applicationName)"],
                    shortTitle: "Heute",
                    systemImageName: "calendar.day.timeline.left")
        AppShortcut(intent: NextEventIntent(),
                    phrases: ["Nächster Termin in \(.applicationName)",
                              "Was kommt als Nächstes in \(.applicationName)"],
                    shortTitle: "Nächster Termin",
                    systemImageName: "clock")
        AppShortcut(intent: PlanTaskIntent(),
                    phrases: ["Plane etwas ein mit \(.applicationName)",
                              "Neue Aufgabe in \(.applicationName)"],
                    shortTitle: "Einplanen",
                    systemImageName: "wand.and.stars")
    }
}
