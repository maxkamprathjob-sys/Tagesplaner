import SwiftUI
import PlannerCore

/// Zeigt einen Planungsvorschlag – oder erklärt, warum nichts passt.
/// Es wird erst eingeplant, wenn der Benutzer zustimmt.
struct SuggestionSheet: View {
    @State var session: PlanningSession
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAllCandidates = false
    @State private var manual: ManualTimeRequest?
    @State private var info: String?

    var body: some View {
        NavigationStack {
            Group {
                if let item = store.item(id: session.itemID) {
                    content(item)
                } else {
                    Text("Der Eintrag existiert nicht mehr.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .sheet(item: $manual) { request in
                ManualTimeView(request: request) { interval in
                    if let item = store.item(id: session.itemID) {
                        commit(item, interval)
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: Inhalt

    @ViewBuilder
    private func content(_ item: PlanItem) -> some View {
        let minutes = item.estimatedMinutes ?? settings.defaultTaskMinutes
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").foregroundStyle(Theme.accentText)
                Text("\(item.title) · \(DurationText.exact(minutes))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            switch session.result {
            case .suggestion(let s):
                suggestionView(item, s)
            case .noFit(let n):
                noFitView(item, n, minutes: minutes)
            }

            if let info {
                Text(info)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func suggestionView(_ item: PlanItem, _ s: Suggestion) -> some View {
        let candidates = s.allCandidates
        let index = min(session.candidateIndex, candidates.count - 1)
        let chosen = candidates[index]

        Text("Ich würde „\(item.title)“ \(dayPhrase(chosen.start)) von \(Fmt.time(chosen.start))–\(Fmt.time(chosen.end)) Uhr einplanen.")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

        if let w = s.deadlineWarning {
            Label(w, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        if let d = item.deadline, chosen.end > d {
            Label("Dieser Zeitraum endet nach der Deadline (\(Fmt.time(d))).", systemImage: "flag")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }

        VStack(spacing: 10) {
            PrimaryButton(title: "Einplanen", systemImage: "checkmark") { commit(item, chosen) }
            HStack(spacing: 10) {
                SecondaryButton(title: "Andere Zeit", systemImage: "arrow.triangle.2.circlepath") {
                    if session.candidateIndex + 1 < candidates.count {
                        session.candidateIndex += 1
                    } else {
                        showAllCandidates = true
                    }
                }
                SecondaryButton(title: "Nicht jetzt", systemImage: "xmark") {
                    ui.showToast("„\(item.title)“ bleibt in deiner To-do-Liste.")
                    dismiss()
                }
            }
        }

        if showAllCandidates || session.candidateIndex > 0 {
            DisclosureGroup("Alle Möglichkeiten", isExpanded: $showAllCandidates) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { i, c in
                        Button {
                            session.candidateIndex = i
                        } label: {
                            HStack {
                                Text("\(dayPhrase(c.start).capitalizedFirst) \(Fmt.range(c.start, c.end))")
                                Spacer()
                                if i == index { Image(systemName: "checkmark") }
                            }
                        }
                        .foregroundStyle(i == index ? Theme.accentText : Theme.textPrimary)
                    }
                    Button("Anderen Tag suchen …") { searchOtherDay(item) }
                    Button("Uhrzeit selbst wählen …") {
                        manual = ManualTimeRequest(start: chosen.start, minutes: Int(chosen.duration / 60))
                    }
                }
                .font(.subheadline)
                .padding(.top, 6)
            }
            .tint(Theme.accentText)
        }
    }

    @ViewBuilder
    private func noFitView(_ item: PlanItem, _ n: NoFit, minutes: Int) -> some View {
        let isToday = Calendar.current.isDateInToday(session.day)
        let dayWord = isToday ? "Dein heutiger Tag" : "Dieser Tag"
        Text(n.totalFreeMinutes < 15
             ? "\(dayWord) ist bereits vollständig verplant."
             : "\(dayWord) ist bereits stark ausgelastet. Für „\(item.title)“ fehlen ungefähr \(DurationText.approximate(n.missingMinutes)).")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

        if session.window != nil {
            Text("Im gewünschten Zeitfenster ist nicht genug Platz.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        if n.largestGapMinutes > 0 {
            Text("Größte freie Lücke: ungefähr \(DurationText.approximate(n.largestGapMinutes)).")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        if let late = n.afterBedtime {
            Label("Es würde nur nach deiner Schlafenszeit (\(settings.bedtime.formatted)) passen: \(Fmt.range(late.start, late.end)).",
                  systemImage: "moon")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        if n.deadlineBlocksNextDay {
            Label("Ein Verschieben auf morgen gefährdet die Deadline.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(Theme.warning)
        }

        VStack(spacing: 10) {
            PrimaryButton(title: "Auf morgen verschieben", systemImage: "arrow.right") {
                let tomorrow = DayMath.addDays(1, to: session.day, calendar: store.calendar)
                store.move(item, toDay: tomorrow)
                session = PlanningSession(itemID: item.id, day: tomorrow, window: nil,
                                          result: store.suggestion(for: item, on: tomorrow))
                ui.go(to: tomorrow)
            }
            HStack(spacing: 10) {
                SecondaryButton(title: isToday ? "Heute trotzdem" : "Trotzdem einplanen", systemImage: "plus") {
                    let start = n.afterBedtime?.start ?? defaultManualStart()
                    manual = ManualTimeRequest(start: start, minutes: minutes)
                }
                SecondaryButton(title: "Andere Zeit suchen", systemImage: "magnifyingglass") {
                    searchOtherDay(item)
                }
            }
            SecondaryButton(title: "Aufgabe bearbeiten", systemImage: "pencil") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    ui.editor = EditorRequest(item: item, defaultStart: nil, defaultDay: item.day, asTask: item.isTask)
                }
            }
        }
    }

    // MARK: Aktionen

    private func commit(_ item: PlanItem, _ interval: DateInterval) {
        store.schedule(item, at: interval)
        let collisions = ConflictDetector.collisions(of: interval, ignoring: item.id.uuidString,
                                                     in: store.scheduleEntries(around: interval.start))
        if collisions.isEmpty {
            ui.showToast("Eingeplant: \(Fmt.relativeDayName(interval.start) ?? Fmt.shortDay(interval.start)) \(Fmt.range(interval.start, interval.end))")
        } else {
            ui.showToast("Eingeplant – überschneidet sich mit \(collisions.map(\.title).joined(separator: ", "))")
        }
        ui.go(to: interval.start)
        dismiss()
    }

    private func searchOtherDay(_ item: PlanItem) {
        let start = DayMath.addDays(1, to: session.day, calendar: store.calendar)
        if let fit = store.firstFit(for: item, from: start, days: 7) {
            session = PlanningSession(itemID: item.id, day: fit.day, window: nil, result: .suggestion(fit.suggestion))
            showAllCandidates = false
            info = nil
        } else {
            info = "In den nächsten 7 Tagen gibt es keine passende Lücke. Du kannst die Dauer verkürzen oder selbst eine Zeit wählen."
        }
    }

    private func defaultManualStart() -> Date {
        let base = max(store.now, store.dayInterval(session.day).start)
        return DayMath.roundUp(base, toMinutes: 15, calendar: store.calendar)
    }

    private func dayPhrase(_ date: Date) -> String {
        if let rel = Fmt.relativeDayName(date) { return rel.lowercased() }
        return "am " + Fmt.shortDay(date)
    }
}

struct ManualTimeRequest: Identifiable {
    let id = UUID()
    var start: Date
    var minutes: Int
}

/// Manuelle Zeitwahl (z. B. "Heute trotzdem einplanen").
struct ManualTimeView: View {
    let request: ManualTimeRequest
    let onConfirm: (DateInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var minutes = 60

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Beginn", selection: $start)
                Stepper("Dauer: \(DurationText.exact(minutes))", value: $minutes, in: 5...(16 * 60), step: 15)
                Text("Ende: \(Fmt.time(start.addingTimeInterval(TimeInterval(minutes * 60))))")
                    .foregroundStyle(Theme.textSecondary)
            }
            .navigationTitle("Zeit wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Einplanen") {
                        onConfirm(DateInterval(start: start, duration: TimeInterval(minutes * 60)))
                        dismiss()
                    }
                }
            }
            .onAppear {
                start = request.start
                minutes = request.minutes
            }
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

extension String {
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}
