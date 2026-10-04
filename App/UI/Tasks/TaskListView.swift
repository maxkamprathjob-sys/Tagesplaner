import SwiftUI
import PlannerCore

/// To-do-Liste und Termine des gewählten Tages.
/// Zeigt dieselben Einträge wie der Tagesplan – keine Kopien.
struct TaskListView: View {
    let day: Date
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var calendarService: CalendarService
    @State private var showDone = false

    var body: some View {
        let _ = store.revision
        let _ = calendarService.revision
        let tasks = store.tasks(on: day)
        let open = sortOpen(tasks.filter { !$0.isDone })
        let done = tasks.filter(\.isDone)
        let appointments = store.appointments(on: day)
        let external = store.externalEvents(on: day)
        let isToday = Calendar.current.isDateInToday(day)
        let overdue = isToday ? store.overdueTasks(before: day) : []
        let warnings = isToday ? store.deadlineWarnings().filter { !Calendar.current.isDate($0.item.day, inSameDayAs: day) } : []
        let unplannedCount = open.filter { !$0.isScheduled }.count

        List {
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings.map { $0.item }) { item in
                        TaskRow(item: item, showDay: true)
                    }
                } header: {
                    sectionHeader("Deadlines in Gefahr", systemImage: "exclamationmark.triangle")
                }
            }

            if !overdue.isEmpty {
                Section {
                    ForEach(overdue) { item in
                        TaskRow(item: item, showDay: true)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Auf heute") { store.move(item, toDay: Date()) }
                                    .tint(Theme.accent)
                            }
                    }
                } header: {
                    sectionHeader("Liegen geblieben", systemImage: "tray")
                }
            }

            Section {
                if open.isEmpty {
                    Text(tasks.isEmpty ? "Keine Aufgaben für diesen Tag." : "Alles erledigt.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(open) { item in
                        TaskRow(item: item, showDay: false)
                    }
                }
                Button {
                    ui.editor = EditorRequest(item: nil, defaultStart: nil, defaultDay: day, asTask: true)
                } label: {
                    Label("Aufgabe hinzufügen", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentText)
                }
            } header: {
                HStack {
                    sectionHeader("Aufgaben", systemImage: "checklist")
                    Spacer()
                    if unplannedCount > 0 && store.dayInterval(day).end > store.now {
                        Button {
                            ui.showPlanDay = true
                        } label: {
                            Label("Tag planen", systemImage: "wand.and.stars")
                                .font(.caption.weight(.semibold))
                        }
                        .textCase(nil)
                        .foregroundStyle(Theme.accentText)
                    }
                }
            }

            if !appointments.isEmpty || !external.isEmpty {
                Section {
                    ForEach(appointments) { item in
                        TaskRow(item: item, showDay: false)
                    }
                    ForEach(external) { e in
                        ExternalEventRow(event: e)
                    }
                } header: {
                    sectionHeader("Termine", systemImage: "calendar")
                }
            }

            if !done.isEmpty {
                Section {
                    if showDone {
                        ForEach(done) { item in TaskRow(item: item, showDay: false) }
                    }
                } header: {
                    Button {
                        withAnimation { showDone.toggle() }
                    } label: {
                        HStack {
                            sectionHeader("Erledigt (\(done.count))", systemImage: "checkmark.circle")
                            Spacer()
                            Image(systemName: showDone ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textSecondary)
    }

    /// Eingeplante Aufgaben nach Uhrzeit, danach ungeplante nach Priorität und Deadline.
    private func sortOpen(_ items: [PlanItem]) -> [PlanItem] {
        items.sorted { a, b in
            switch (a.start, b.start) {
            case let (sa?, sb?): return sa < sb
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.priority != b.priority { return a.priority > b.priority }
                return (a.deadline ?? .distantFuture) < (b.deadline ?? .distantFuture)
            }
        }
    }
}

struct TaskRow: View {
    let item: PlanItem
    let showDay: Bool
    var assessment: DeadlineAssessment? = nil
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        let deadlineInfo = assessment ?? store.deadlineAssessment(for: item)
        HStack(alignment: .top, spacing: 12) {
            if item.isTask {
                Button {
                    withAnimation { store.setDone(item, !item.isDone) }
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(item.isDone ? Theme.accentText : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isDone ? "Als offen markieren" : "Als erledigt markieren")
            } else {
                Image(systemName: item.category.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.body)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? Theme.textSecondary : Theme.textPrimary)
                    if item.priority >= .high {
                        Text(item.priority == .veryHigh ? "!!!" : "!!")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.accentText)
                            .accessibilityLabel("Priorität \(item.priority.label)")
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if let a = deadlineInfo, a.level != .ok, let message = a.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if item.isTask && !item.isDone && !item.isScheduled {
                Button {
                    ui.startPlanning(item, store: store)
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Einplanen")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ui.editor = EditorRequest(item: item, defaultStart: nil, defaultDay: item.day, asTask: item.isTask)
        }
        .listRowBackground(Theme.surface)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.isTask {
                Button(item.isDone ? "Offen" : "Erledigt") { store.setDone(item, !item.isDone) }
                    .tint(Theme.accent)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Löschen", role: .destructive) { store.delete(item) }
            Button("Morgen") {
                store.move(item, toDay: Calendar.current.date(byAdding: .day, value: 1, to: item.day) ?? item.day)
            }
            .tint(.gray)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if showDay {
            parts.append(Fmt.relativeDayName(item.day) ?? Fmt.shortDay(item.day))
        }
        if let iv = item.interval {
            parts.append(Fmt.range(iv.start, iv.end) + (item.isOvernight ? " (+1 Tag)" : ""))
        } else if let m = item.estimatedMinutes {
            parts.append("≈ \(DurationText.exact(m)) · nicht eingeplant")
        } else if item.isTask {
            parts.append("ohne Uhrzeit")
        }
        if let d = item.deadline {
            let dayName = Fmt.relativeDayName(d) ?? Fmt.shortDay(d)
            parts.append("bis \(dayName) \(Fmt.time(d))")
        }
        if item.category != .other { parts.append(item.category.label) }
        return parts.joined(separator: " · ")
    }
}

struct ExternalEventRow: View {
    let event: ExternalEvent
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.body)
                Text(event.isAllDay ? "Ganztägig · \(event.calendarName)" : "\(Fmt.range(event.start, event.end)) · \(event.calendarName)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .listRowBackground(Theme.surface)
        .accessibilityHint("Termin aus dem Apple-Kalender, nur lesbar")
    }
}
