import SwiftUI
import PlannerCore

/// Schnelleingabe: "+" → Text → (optional Zeit) → Speichern.
/// Der Text wird lokal verstanden; erkannte Angaben erscheinen sofort als Chips.
struct QuickAddView: View {
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var kind: Kind = .auto
    @State private var manualTime = false
    @State private var manualStart = Date()
    @State private var manualEnd = Date().addingTimeInterval(3600)
    @FocusState private var focused: Bool

    enum Kind: String, CaseIterable, Identifiable {
        case auto = "Automatisch"
        case task = "Aufgabe"
        case appointment = "Termin"
        var id: String { rawValue }
    }

    private var parser: NaturalLanguageParser { NaturalLanguageParser(calendar: store.calendar) }

    var body: some View {
        let parsed = effectiveParse()
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("z. B. Morgen 2 Stunden für die Klausur lernen", text: $text, axis: .vertical)
                    .font(.title3)
                    .lineLimit(1...3)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    ParsedChips(parsed: parsed, selectedDay: ui.selectedDay, asTask: isTask(parsed))
                }

                Picker("Art", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Uhrzeit selbst festlegen", isOn: $manualTime.animation())
                    .font(.subheadline)
                    .onChange(of: manualTime) { _, on in
                        if on { prefillManualTime(from: parser.parse(text, now: store.now)) }
                    }
                if manualTime {
                    DatePicker("Beginn", selection: $manualStart)
                    DatePicker("Ende", selection: $manualEnd)
                    if manualEnd <= manualStart {
                        Text("Ende liegt vor dem Beginn – der Block endet am Folgetag.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text("Ohne Uhrzeit, aber mit Dauer schlägt die App dir einen freien Zeitraum vor – eingeplant wird erst nach deiner Bestätigung.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(16)
            .navigationTitle("Neuer Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", action: save)
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Mehr Details …") {
                        dismiss()
                        ui.editor = EditorRequest(item: nil, defaultStart: nil, defaultDay: ui.selectedDay,
                                                  asTask: kind != .appointment)
                    }
                    .font(.subheadline)
                }
            }
            .onAppear {
                focused = true
                let base = TimeOfDay(minutesSinceMidnight: ((TimeOfDay(Date()).minutesSinceMidnight / 15) + 1) * 15)
                manualStart = base.date(on: ui.selectedDay, calendar: Calendar.current)
                manualEnd = manualStart.addingTimeInterval(3600)
            }
        }
    }

    /// Parse-Ergebnis inkl. manuell gesetzter Zeit.
    private func effectiveParse() -> ParsedInput {
        var p = parser.parse(text, now: store.now)
        if manualTime {
            let cal = Calendar.current
            p.day = cal.startOfDay(for: manualStart)
            p.startTime = TimeOfDay(manualStart)
            p.endTime = TimeOfDay(manualEnd)
            if p.endTime == p.startTime { p.endTime = nil; p.durationMinutes = p.durationMinutes ?? settings.defaultTaskMinutes }
        }
        return p
    }

    private func isTask(_ p: ParsedInput) -> Bool {
        switch kind {
        case .task: return true
        case .appointment: return false
        case .auto:
            if p.isSleep { return false }
            // Mit fester Uhrzeit und typischer Termin-Kategorie → Termin, sonst Aufgabe.
            if p.hasFixedTime { return !ItemCategory.guess(from: p.title).isFixedByDefault }
            return true
        }
    }

    private func prefillManualTime(from p: ParsedInput) {
        let day = p.day ?? ui.selectedDay
        if let iv = p.interval(defaultDay: day, calendar: Calendar.current) {
            manualStart = iv.start
            manualEnd = iv.end
        } else if let start = p.startTime {
            manualStart = start.date(on: day, calendar: Calendar.current)
            manualEnd = manualStart.addingTimeInterval(TimeInterval((p.durationMinutes ?? settings.defaultTaskMinutes) * 60))
        } else if let minutes = p.durationMinutes {
            manualEnd = manualStart.addingTimeInterval(TimeInterval(minutes * 60))
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parsed = effectiveParse()
        let result = store.create(from: parsed, selectedDay: ui.selectedDay, asTask: isTask(parsed))
        let item = result.item
        dismiss()

        ui.go(to: item.day)
        if result.needsSuggestion {
            // Kurze Verzögerung, damit sich das Eingabe-Sheet erst schließt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                ui.startPlanning(item, on: item.day, window: result.window, store: store)
            }
        } else if !result.collisions.isEmpty {
            let names = result.collisions.map(\.title).joined(separator: ", ")
            ui.showToast("Achtung: überschneidet sich mit \(names)")
        } else if let iv = item.interval {
            ui.showToast("\(item.title): \(Fmt.relativeDayName(iv.start) ?? Fmt.shortDay(iv.start)) \(Fmt.range(iv.start, iv.end))")
        } else {
            ui.showToast("„\(item.title)“ hinzugefügt")
        }
    }
}

/// Zeigt, was aus der Eingabe erkannt wurde.
struct ParsedChips: View {
    let parsed: ParsedInput
    let selectedDay: Date
    let asTask: Bool

    var body: some View {
        let day = parsed.day ?? selectedDay
        VStack(alignment: .leading, spacing: 8) {
            Text(parsed.title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            FlowRow {
                chip(asTask ? "Aufgabe" : (parsed.isSleep ? "Schlaf" : "Termin"), "tag")
                chip(Fmt.relativeDayName(day) ?? Fmt.shortDay(day), "calendar")
                if let iv = parsed.interval(defaultDay: day, calendar: Calendar.current) {
                    chip(Fmt.range(iv.start, iv.end) + (Calendar.current.isDate(iv.start, inSameDayAs: iv.end) ? "" : " (+1)"), "clock")
                } else if let s = parsed.startTime {
                    chip("ab \(s.formatted)", "clock")
                }
                if let m = parsed.durationMinutes {
                    chip(DurationText.exact(m), "hourglass")
                }
                if let d = parsed.deadline {
                    chip("bis \(Fmt.relativeDayName(d) ?? Fmt.shortDay(d)) \(Fmt.time(d))", "flag")
                }
                if let p = parsed.priority {
                    chip(p.label, "exclamationmark")
                }
                if let a = parsed.afterItem, let b = parsed.beforeItem {
                    chip("zwischen \(a) und \(b)", "arrow.left.and.right")
                } else if let a = parsed.afterItem {
                    chip("nach \(a)", "arrow.right")
                } else if let b = parsed.beforeItem {
                    chip("vor \(b)", "arrow.left")
                }
            }
        }
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accentFill, in: Capsule())
            .foregroundStyle(Theme.accentText)
    }
}

/// Einfacher umbrechender Zeilen-Layout für Chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            width = max(width, x)
        }
        return CGSize(width: min(width, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
