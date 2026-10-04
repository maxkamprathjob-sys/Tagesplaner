import WidgetKit
import SwiftUI

@main
struct TagesplanerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextUpWidget()
        OpenTasksWidget()
        DayLiveActivityWidget()
    }
}

// MARK: - Timeline

struct PlanEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Liest den Snapshot der App und erzeugt Einträge zu jedem Blockwechsel,
/// damit "Jetzt"/"Nächster" ohne Neuladen stimmen.
struct PlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanEntry {
        PlanEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanEntry) -> Void) {
        completion(PlanEntry(date: Date(), snapshot: SnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotStore.read()
        var dates = [now]
        if let s = snapshot {
            dates += s.changeDates(after: now).prefix(40)
        }
        let entries = dates.map { PlanEntry(date: $0, snapshot: snapshot) }
        // Nach dem letzten Eintrag neu laden; spätestens nach 6 Stunden.
        let reload = min(dates.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(3600),
                         now.addingTimeInterval(6 * 3600))
        completion(Timeline(entries: entries, policy: .after(max(reload, now.addingTimeInterval(300)))))
    }
}

// MARK: - Gemeinsame Bausteine

struct EmptyStateText: View {
    let snapshot: WidgetSnapshot?
    var body: some View {
        Text(snapshot == nil ? "Öffne die App einmal, um das Widget zu füllen." : "Heute steht nichts mehr an.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct BlockLine: View {
    let item: WidgetSnapshot.Item
    let now: Date
    var compact = false

    var body: some View {
        let running = item.start <= now && item.end > now
        HStack(spacing: 6) {
            Text(item.start < Calendar.current.startOfDay(for: now) ? "  ↳  " : Fmt.time(item.start))
                .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(running ? Theme.accentText : .secondary)
            Text(item.title)
                .font(.system(size: compact ? 12 : 13, weight: running ? .bold : .medium))
                .lineLimit(1)
                .strikethrough(item.isDone)
            Spacer(minLength: 0)
        }
    }
}
