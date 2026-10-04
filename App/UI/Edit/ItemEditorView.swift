import SwiftUI
import PlannerCore

/// Bearbeiten oder Anlegen eines Eintrags (Aufgabe, Zeitblock oder beides).
/// Änderungen werden erst beim Sichern übernommen – Abbrechen verwirft sie.
struct ItemEditorView: View {
    let request: EditorRequest
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var category: ItemCategory = .other
    @State private var categoryTouched = false
    @State private var isTask = true
    @State private var isDone = false
    @State private var isFixed = false
    @State private var hasTime = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var hasEstimate = false
    @State private var estimate = 60
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var priority: Priority = .normal
    @State private var day = Date()
    @State private var confirmDelete = false
    @State private var loaded = false

    private var isNew: Bool { request.item == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $title)
                        .font(.headline)
                        .onChange(of: title) { _, newValue in
                            if !categoryTouched { category = ItemCategory.guess(from: newValue) }
                        }
                    Picker("Kategorie", selection: Binding(get: { category }, set: { category = $0; categoryTouched = true })) {
                        ForEach(ItemCategory.allCases) { c in
                            Label(c.label, systemImage: c.symbol).tag(c)
                        }
                    }
                }

                Section {
                    Toggle("In der To-do-Liste", isOn: $isTask)
                    if isTask {
                        Toggle("Erledigt", isOn: $isDone)
                    }
                    Toggle("Zeitblock im Tagesplan", isOn: $hasTime.animation())
                    if hasTime {
                        // Dauer beibehalten, wenn der Beginn verschoben wird
                        DatePicker("Beginn", selection: Binding(
                            get: { start },
                            set: { new in
                                end = end.addingTimeInterval(new.timeIntervalSince(start))
                                start = new
                            }))
                        DatePicker("Ende", selection: $end)
                        if let note = intervalNote {
                            Text(note).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Toggle("Fester Termin", isOn: $isFixed)
                        if !collisions.isEmpty {
                            Label("Überschneidet sich mit \(collisions.map(\.title).joined(separator: ", "))",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                        }
                    } else {
                        DatePicker("Tag", selection: $day, displayedComponents: .date)
                    }
                } header: {
                    Text("Wann")
                } footer: {
                    if hasTime && isTask {
                        Text("Erscheint im Tagesplan und in der To-do-Liste – es ist derselbe Eintrag.")
                    }
                }

                if isTask {
                    Section("Planung") {
                        Picker("Priorität", selection: $priority) {
                            ForEach(Priority.allCases) { Text($0.label).tag($0) }
                        }
                        Toggle("Geschätzte Dauer", isOn: $hasEstimate)
                        if hasEstimate {
                            Stepper(DurationText.exact(estimate), value: $estimate, in: 5...(12 * 60), step: 15)
                        }
                        Toggle("Deadline", isOn: $hasDeadline)
                        if hasDeadline {
                            DatePicker("Fällig", selection: $deadline)
                        }
                    }
                }

                Section("Notiz") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let item = request.item {
                    Section {
                        if item.isTask && !item.isScheduled && !hasTime {
                            Button {
                                save(close: false)
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    ui.startPlanning(item, store: store)
                                }
                            } label: {
                                Label("Freie Zeit vorschlagen lassen", systemImage: "wand.and.stars")
                            }
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isNew ? "Neuer Eintrag" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save(close: true) }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .confirmationDialog("Eintrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let item = request.item { store.delete(item) }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Validierung

    private var normalizedInterval: DateInterval? {
        DayMath.normalizedInterval(start: start, end: end, calendar: Calendar.current)
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if hasTime { return normalizedInterval != nil }
        return true
    }

    private var intervalNote: String? {
        guard hasTime else { return nil }
        guard let iv = normalizedInterval else { return "Beginn und Ende sind identisch." }
        let minutes = DayMath.minutes(iv)
        if end <= start { return "Endet am Folgetag um \(Fmt.time(iv.end)) · \(DurationText.exact(minutes))" }
        return "Dauer: \(DurationText.exact(minutes))"
    }

    private var collisions: [ScheduleEntry] {
        guard let iv = normalizedInterval else { return [] }
        return ConflictDetector.collisions(of: iv, ignoring: request.item?.id.uuidString,
                                           in: store.scheduleEntries(around: iv.start))
    }

    // MARK: Laden / Sichern

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let item = request.item {
            title = item.title
            notes = item.notes
            category = item.category
            categoryTouched = true
            isTask = item.isTask
            isDone = item.isDone
            isFixed = item.isFixed
            priority = item.priority
            day = item.day
            if let iv = item.interval {
                hasTime = true
                start = iv.start
                end = iv.end
            } else {
                start = defaultStart(on: item.day)
                end = start.addingTimeInterval(TimeInterval((item.estimatedMinutes ?? settings.defaultTaskMinutes) * 60))
            }
            if let m = item.estimatedMinutes { hasEstimate = true; estimate = m }
            if let d = item.deadline { hasDeadline = true; deadline = d }
            else { deadline = TimeOfDay(hour: 18).date(on: item.day, calendar: Calendar.current) }
        } else {
            isTask = request.asTask
            day = Calendar.current.startOfDay(for: request.defaultDay)
            hasTime = request.defaultStart != nil
            start = request.defaultStart ?? defaultStart(on: request.defaultDay)
            end = start.addingTimeInterval(3600)
            isFixed = !request.asTask
            deadline = TimeOfDay(hour: 18).date(on: request.defaultDay, calendar: Calendar.current)
        }
    }

    private func defaultStart(on day: Date) -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(day) {
            return DayMath.roundUp(Date(), toMinutes: 15, calendar: cal)
        }
        return TimeOfDay(hour: 9).date(on: day, calendar: cal)
    }

    private func save(close: Bool) {
        guard isValid else { return }
        let item: PlanItem
        if let existing = request.item {
            item = existing
        } else {
            item = PlanItem(title: title, day: day, calendar: store.calendar)
            store.context.insert(item)
        }
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.notes = notes
        item.category = category
        item.isTask = isTask
        if item.isDone != (isTask && isDone) { item.setDone(isTask && isDone) }
        item.priority = priority
        item.estimatedMinutes = hasEstimate ? estimate : (hasTime ? normalizedInterval.map { DayMath.minutes($0) } : nil)
        item.deadline = (isTask && hasDeadline) ? deadline : nil
        if hasTime, let iv = normalizedInterval {
            item.isFixed = isFixed
            item.setSchedule(iv, calendar: store.calendar)
        } else {
            item.isFixed = false
            item.setSchedule(nil, calendar: store.calendar)
            item.day = store.calendar.startOfDay(for: day)
        }
        item.touch()
        store.commitEdit()
        if close {
            ui.go(to: item.day)
            dismiss()
        }
    }
}
