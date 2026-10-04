import Foundation
import WidgetKit
import PlannerCore

/// Schreibt nach jeder Änderung den Widget-Snapshot und lädt die Widgets neu.
enum WidgetSync {

    static func makeSnapshot(items: [PlanItem], externalEvents: [ExternalEvent],
                             now: Date, calendar: Calendar) -> WidgetSnapshot {
        let from = DayMath.addDays(-1, to: now, calendar: calendar)
        let to = DayMath.addDays(4, to: now, calendar: calendar)

        var blocks: [WidgetSnapshot.Item] = items.compactMap { item in
            guard let iv = item.interval, iv.end > from, iv.start < to else { return nil }
            return WidgetSnapshot.Item(id: item.id.uuidString, title: item.title,
                                       start: iv.start, end: iv.end, symbol: item.category.symbol,
                                       isTask: item.isTask, isDone: item.isDone,
                                       isExternal: false, isSleep: item.isSleep)
        }
        blocks += externalEvents.filter { !$0.isAllDay && $0.end > from && $0.start < to }.map {
            WidgetSnapshot.Item(id: $0.id, title: $0.title, start: $0.start, end: $0.end,
                                symbol: "calendar", isTask: false, isDone: false,
                                isExternal: true, isSleep: false)
        }

        var open: [String: [WidgetSnapshot.OpenTask]] = [:]
        for item in items where item.isTask && !item.isDone && item.day >= from && item.day < to {
            let key = WidgetSnapshot.dayKey(item.day, calendar: calendar)
            open[key, default: []].append(WidgetSnapshot.OpenTask(
                id: item.id.uuidString, title: item.title, deadline: item.deadline,
                priority: item.priorityRaw, minutes: item.plannedMinutes))
        }
        for key in open.keys {
            open[key]?.sort { a, b in
                if a.priority != b.priority { return a.priority > b.priority }
                return (a.deadline ?? .distantFuture) < (b.deadline ?? .distantFuture)
            }
        }
        return WidgetSnapshot(generatedAt: now, items: blocks.sorted { $0.start < $1.start }, openTasks: open)
    }

    /// Gibt eine Fehlermeldung zurück, statt abzustürzen.
    @discardableResult
    static func publish(_ snapshot: WidgetSnapshot) -> String? {
        do {
            try SnapshotStore.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            return nil
        } catch {
            return "Widgets konnten nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }
}
