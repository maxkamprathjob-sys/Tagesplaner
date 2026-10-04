import Foundation
import ActivityKit

/// Ein Block für Live Activity / Widgets (App-Eintrag oder Kalendertermin).
struct TimelineBlock: Hashable {
    var id: String
    var title: String
    var symbol: String
    var start: Date
    var end: Date
    var isSleep: Bool
}

/// Zeigt den laufenden Zeitblock als Live Activity auf dem Sperrbildschirm
/// und in der Dynamic Island.
///
/// iOS-Grenzen (bewusst so umgesetzt):
/// - Eine Live Activity kann ohne eigenen Push-Server nur gestartet werden,
///   während die App im Vordergrund ist. Sie startet daher beim Öffnen der App
///   (bzw. bei jeder Änderung), wenn gerade ein Block läuft.
/// - Am Blockende wird sie als "abgelaufen" markiert und zeigt den nächsten Block an.
///   Beim nächsten Öffnen der App wird sie aktualisiert oder beendet.
/// - iOS beendet Live Activities spätestens nach 8 Stunden.
@MainActor
final class LiveActivityService {

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func sync(enabled: Bool, blocks: [TimelineBlock], now: Date) async {
        let activities = Activity<DayActivityAttributes>.activities
        guard enabled, isAvailable else {
            for a in activities { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let sorted = blocks.sorted { $0.start < $1.start }
        let current = sorted.filter { !$0.isSleep && $0.start <= now && $0.end > now }
            .sorted { $0.start > $1.start }
            .first
        guard let block = current else {
            for a in activities { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let next = sorted.first { $0.start >= block.end.addingTimeInterval(-60) && $0.id != block.id && !$0.isSleep }
            ?? sorted.first { $0.start > now && $0.id != block.id }

        let state = DayActivityAttributes.ContentState(title: block.title, symbol: block.symbol,
                                                       start: block.start, end: block.end,
                                                       nextTitle: next?.title, nextStart: next?.start)
        let content = ActivityContent(state: state, staleDate: block.end)

        var kept = false
        for a in activities {
            if a.attributes.itemID == block.id && !kept {
                await a.update(content)
                kept = true
            } else {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard !kept else { return }
        do {
            _ = try Activity<DayActivityAttributes>.request(attributes: DayActivityAttributes(itemID: block.id), content: content, pushType: nil)
        } catch {
            // Nicht verfügbar oder vom Benutzer deaktiviert – die App funktioniert ohne weiter.
        }
    }

    func endAll() async {
        for a in Activity<DayActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }
}
