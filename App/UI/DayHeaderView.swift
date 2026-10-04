import SwiftUI
import PlannerCore

/// "HEUTE / Mittwoch, 28. Oktober" mit Tageswechsel.
struct DayHeaderView: View {
    @EnvironmentObject private var ui: UIState
    @State private var showPicker = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text((Fmt.relativeDayName(ui.selectedDay) ?? weekday).uppercased())
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .tracking(1.5)
                    .foregroundStyle(ui.isToday ? Theme.accentText : Theme.textPrimary)
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(Fmt.day(ui.selectedDay))
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel("Datum wählen, aktuell \(Fmt.day(ui.selectedDay))")
            }
            Spacer()
            if !ui.isToday {
                Button("Heute") { withAnimation { ui.go(to: Date()) } }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
            }
            HStack(spacing: 4) {
                navButton("chevron.left", label: "Vorheriger Tag") { ui.shiftDay(-1) }
                navButton("chevron.right", label: "Nächster Tag") { ui.shiftDay(1) }
            }
            Button {
                ui.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel("Einstellungen")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation { ui.shiftDay(value.translation.width < 0 ? 1 : -1) }
            }
        )
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("Datum", selection: Binding(
                    get: { ui.selectedDay },
                    set: { ui.go(to: $0); showPicker = false }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "de_DE"))
                .padding()
                .navigationTitle("Tag wählen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { showPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Heute") { ui.go(to: Date()); showPicker = false }
                    }
                }
                Spacer()
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var weekday: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE"
        return f.string(from: ui.selectedDay)
    }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityLabel(label)
    }
}

/// Tagesanalyse: freie Zeit, Auslastung, Konflikte.
struct DayLoadBanner: View {
    let day: Date
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarService: CalendarService
    @State private var showConflicts = false

    var body: some View {
        let _ = store.revision
        let _ = calendarService.revision
        let load = store.dayLoad(on: day)
        let conflicts = store.conflicts(on: day)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(load.level))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color(load.level))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(load.headline)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = load.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if !conflicts.isEmpty {
                Button {
                    showConflicts = true
                } label: {
                    Label(conflicts.count == 1 ? "1 Überschneidung" : "\(conflicts.count) Überschneidungen",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.warning)
                }
                .padding(.leading, 28)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showConflicts) {
            ConflictListView(conflicts: conflicts)
                .presentationDetents([.medium])
        }
    }

    private func icon(_ level: DayLoad.Level) -> String {
        switch level {
        case .past: return "clock.arrow.circlepath"
        case .relaxed: return "circle.dotted"
        case .balanced: return "circle.lefthalf.filled"
        case .tight: return "exclamationmark.circle"
        case .full: return "circle.fill"
        }
    }

    private func color(_ level: DayLoad.Level) -> Color {
        switch level {
        case .tight, .full: return Theme.warning
        case .past: return Theme.textSecondary
        default: return Theme.accentText
        }
    }
}

struct ConflictListView: View {
    let conflicts: [Conflict]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(conflicts, id: \.self) { c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.message).font(.subheadline)
                    Text("\(Fmt.range(c.first.interval.start, c.first.interval.end)) und \(Fmt.range(c.second.interval.start, c.second.interval.end))")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("Überschneidungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Nichts wurde automatisch verschoben. Tippe im Tagesplan auf einen Block, um ihn zu ändern.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding()
            }
        }
    }
}

/// Untere Leiste: großes "+" für die Schnelleingabe.
struct QuickAddBar: View {
    @EnvironmentObject private var ui: UIState

    var body: some View {
        HStack(spacing: 12) {
            Button {
                ui.showQuickAdd = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                    Text("z. B. „morgen 2 Stunden lernen“")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
            }
            .foregroundStyle(Theme.accentText)
            .accessibilityLabel("Neuer Eintrag")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.background.opacity(0.95))
    }
}
