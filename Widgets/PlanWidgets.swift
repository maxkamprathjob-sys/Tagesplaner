import WidgetKit
import SwiftUI

// MARK: - "Heute" (Sperrbildschirm rechteckig + Home-Bildschirm)

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: PlanProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
                .widgetURL(URL(string: "tagesplaner://today"))
        }
        .configurationDisplayName("Heute")
        .description("Dein Tagesplan: laufender und nächste Blöcke.")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    let entry: PlanEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let now = entry.date
        let remaining = entry.snapshot?.remainingToday(at: now) ?? []
        let visible = remaining.filter { !$0.isSleep || $0.start > now } // laufenden Schlaf nicht anzeigen
        let open = entry.snapshot?.openTasks(on: now) ?? []

        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("HEUTE").font(.system(size: 11, weight: .bold)).widgetAccentable()
                if visible.isEmpty {
                    Text(open.isEmpty ? "Nichts mehr geplant" : "\(open.count) offene Aufgaben")
                        .font(.system(size: 13, weight: .medium))
                } else {
                    ForEach(visible.prefix(3)) { item in
                        BlockLine(item: item, now: now, compact: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                header(now)
                if visible.isEmpty { EmptyStateText(snapshot: entry.snapshot) }
                ForEach(visible.prefix(4)) { BlockLine(item: $0, now: now, compact: true) }
                Spacer(minLength: 0)
                if !open.isEmpty {
                    Text("\(open.count) offen").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accentText)
                }
            }

        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    header(now)
                    if visible.isEmpty { EmptyStateText(snapshot: entry.snapshot) }
                    ForEach(visible.prefix(5)) { BlockLine(item: $0, now: now, compact: true) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                TaskColumn(tasks: Array(open.prefix(5)), total: open.count)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        default:
            VStack(alignment: .leading, spacing: 6) {
                header(now)
                if visible.isEmpty { EmptyStateText(snapshot: entry.snapshot) }
                ForEach(visible.prefix(8)) { item in
                    HStack {
                        BlockLine(item: item, now: now)
                        Text("bis \(Fmt.time(item.end))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Divider()
                TaskColumn(tasks: Array(open.prefix(5)), total: open.count)
                Spacer(minLength: 0)
            }
        }
    }

    private func header(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HEUTE").font(.system(size: 13, weight: .heavy)).tracking(1).foregroundStyle(Theme.accentText)
            Text(Fmt.shortDay(now)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }
}

struct TaskColumn: View {
    let tasks: [WidgetSnapshot.OpenTask]
    let total: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOCH OFFEN").font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(.secondary)
            if tasks.isEmpty {
                Text("Keine offenen Aufgaben").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(tasks) { t in
                HStack(spacing: 5) {
                    Image(systemName: "circle").font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(t.title).font(.system(size: 12)).lineLimit(1)
                    if t.priority >= 2 {
                        Text(t.priority >= 3 ? "!!!" : "!!").font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Theme.accentText)
                    }
                }
            }
            if total > tasks.count {
                Text("+ \(total - tasks.count) weitere").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - "Nächster Termin" (Sperrbildschirm)

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextUpWidget", provider: PlanProvider()) { entry in
            NextUpView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
                .widgetURL(URL(string: "tagesplaner://today"))
        }
        .configurationDisplayName("Nächster Termin")
        .description("Was gerade läuft und was als Nächstes kommt.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall])
    }
}

struct NextUpView: View {
    let entry: PlanEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let now = entry.date
        let current = entry.snapshot?.current(at: now)
        let showCurrent = current.map { !$0.isSleep } ?? false
        let next = entry.snapshot?.upcoming(after: now, limit: 1).first

        switch family {
        case .accessoryInline:
            if let c = current, showCurrent {
                Text("\(c.title) bis \(Fmt.time(c.end))")
            } else if let n = next {
                Text("\(Fmt.time(n.start)) \(n.title)")
            } else {
                Text("Nichts mehr geplant")
            }

        case .accessoryCircular:
            if let c = current, showCurrent {
                ProgressView(timerInterval: c.start...c.end, countsDown: true) {
                    Image(systemName: c.symbol)
                } currentValueLabel: {
                    Image(systemName: c.symbol)
                }
                .progressViewStyle(.circular)
                .widgetAccentable()
            } else if let n = next {
                VStack(spacing: 0) {
                    Image(systemName: n.symbol).font(.system(size: 12))
                    Text(Fmt.time(n.start)).font(.system(size: 13, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.7)
                }
            } else {
                Image(systemName: "checkmark").font(.title3)
            }

        default:
            VStack(alignment: .leading, spacing: 2) {
                if let c = current, showCurrent {
                    Text("JETZT").font(.system(size: 11, weight: .bold)).widgetAccentable()
                    Text(c.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text("noch")
                        Text(timerInterval: now...max(now, c.end), countsDown: true)
                            .monospacedDigit()
                    }
                    .font(.system(size: 12))
                    if let n = next {
                        Text("danach \(Fmt.time(n.start)) \(n.title)").font(.system(size: 12)).lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                } else if let n = next {
                    Text("NÄCHSTER TERMIN").font(.system(size: 11, weight: .bold)).widgetAccentable()
                    Text(n.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(dayPrefix(n.start, now: now) + Fmt.range(n.start, n.end))
                        .font(.system(size: 12, design: .monospaced))
                } else {
                    Text("NÄCHSTER TERMIN").font(.system(size: 11, weight: .bold)).widgetAccentable()
                    EmptyStateText(snapshot: entry.snapshot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dayPrefix(_ date: Date, now: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) { return "" }
        return (Fmt.relativeDayName(date, now: now) ?? Fmt.shortDay(date)) + " "
    }
}

// MARK: - "Offene Aufgaben"

struct OpenTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenTasksWidget", provider: PlanProvider()) { entry in
            OpenTasksView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
                .widgetURL(URL(string: "tagesplaner://tasks"))
        }
        .configurationDisplayName("Offene Aufgaben")
        .description("Wie viele Aufgaben heute noch offen sind.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular, .systemSmall])
    }
}

struct OpenTasksView: View {
    let entry: PlanEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let open = entry.snapshot?.openTasks(on: entry.date) ?? []
        switch family {
        case .accessoryInline:
            Text(open.isEmpty ? "Alles erledigt" : "\(open.count) Aufgaben offen")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(open.count)").font(.system(size: 22, weight: .bold))
                Text("offen").font(.system(size: 10))
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("NOCH OFFEN · \(open.count)").font(.system(size: 11, weight: .bold)).widgetAccentable()
                ForEach(open.prefix(3)) { t in
                    Text("○ \(t.title)").font(.system(size: 12)).lineLimit(1)
                }
                if open.isEmpty { Text("Alles erledigt").font(.system(size: 13)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            TaskColumn(tasks: Array(open.prefix(5)), total: open.count)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
