import SwiftUI
import UserNotifications
import PlannerCore

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarService: CalendarService
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    timePicker("Aufstehen", $settings.wakeTime)
                    timePicker("Schlafenszeit", $settings.bedtime)
                    Stepper("Pause um Termine: \(settings.bufferMinutes) Min.", value: $settings.bufferMinutes, in: 0...60, step: 5)
                    Stepper("Standarddauer: \(DurationText.exact(settings.defaultTaskMinutes))",
                            value: $settings.defaultTaskMinutes, in: 15...240, step: 15)
                } header: {
                    Text("Tag & Schlaf")
                } footer: {
                    Text("Vorschläge liegen immer zwischen Aufstehen und Schlafenszeit. Passt etwas nur noch danach, bekommst du einen Hinweis statt eines Vorschlags.")
                }

                Section {
                    Toggle("Erinnerungen", isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { on in
                            settings.notificationsEnabled = on
                            if on { Task { await enableNotifications() } }
                        }))
                    if settings.notificationsEnabled {
                        Picker("Vorlauf", selection: $settings.notificationLeadMinutes) {
                            ForEach([0, 5, 10, 15, 30, 60], id: \.self) { m in
                                Text(m == 0 ? "Zum Beginn" : "\(m) Min. vorher").tag(m)
                            }
                        }
                        Toggle("Tagesüberblick offener Aufgaben", isOn: $settings.dailySummaryEnabled)
                        if settings.dailySummaryEnabled {
                            timePicker("Uhrzeit", $settings.dailySummaryTime)
                        }
                    }
                    if notificationStatus == .denied {
                        Label("In den iOS-Einstellungen abgelehnt.", systemImage: "bell.slash")
                            .foregroundStyle(Theme.warning)
                        Button("iOS-Einstellungen öffnen") { openSettings() }
                    }
                } header: {
                    Text("Benachrichtigungen")
                }

                Section {
                    Toggle("Apple-Kalender anzeigen", isOn: Binding(
                        get: { settings.calendarEnabled },
                        set: { on in
                            settings.calendarEnabled = on
                            if on && !calendarService.hasAccess {
                                Task {
                                    let granted = await calendarService.requestAccess()
                                    if !granted { settings.calendarEnabled = false }
                                }
                            }
                        }))
                    LabeledContent("Status", value: calendarService.statusText)
                        .font(.footnote)
                    if calendarService.status == .denied {
                        Button("iOS-Einstellungen öffnen") { openSettings() }
                    }
                } header: {
                    Text("Apple-Kalender")
                } footer: {
                    Text("Termine werden nur gelesen, gestrichelt angezeigt und bei der Planung berücksichtigt. Die App verändert deinen Kalender nie.")
                }

                Section {
                    Toggle("Live Activity für laufende Blöcke", isOn: $settings.liveActivityEnabled)
                    if !store.liveActivity.isAvailable {
                        Text("Live Activities sind in den iOS-Einstellungen für diese App deaktiviert.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    NavigationLink("Widgets einrichten") { WidgetHelpView() }
                } header: {
                    Text("Sperrbildschirm")
                } footer: {
                    Text("Die Live Activity zeigt den aktuellen Block mit Restzeit auf dem Sperrbildschirm und in der Dynamic Island. Sie startet, wenn du die App öffnest, während ein Block läuft.")
                }

                Section("Darstellung") {
                    Picker("Erscheinungsbild", selection: $settings.appearance) {
                        ForEach(SettingsStore.Appearance.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Datenschutz") {
                    Label("Alle Daten bleiben auf diesem iPhone.", systemImage: "lock.iphone")
                    Label("Kein Konto, kein Tracking, keine Werbung.", systemImage: "hand.raised")
                    Label("Spracheingaben werden lokal ausgewertet – ohne Cloud-KI.", systemImage: "cpu")
                }
                .font(.footnote)

                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .task {
                notificationStatus = await store.notifications.authorizationStatus()
                calendarService.refreshStatus()
            }
        }
    }

    private func timePicker(_ title: String, _ binding: Binding<TimeOfDay>) -> some View {
        DatePicker(title, selection: Binding(
            get: { binding.wrappedValue.asDate() },
            set: { binding.wrappedValue = TimeOfDay($0) }
        ), displayedComponents: .hourAndMinute)
    }

    private func enableNotifications() async {
        let status = await store.notifications.authorizationStatus()
        if status == .notDetermined {
            let granted = await store.notifications.requestAuthorization()
            if !granted { settings.notificationsEnabled = false }
        } else if status == .denied {
            settings.notificationsEnabled = false
        }
        notificationStatus = await store.notifications.authorizationStatus()
        await store.refreshIntegrations()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

struct WidgetHelpView: View {
    var body: some View {
        List {
            Section("Sperrbildschirm") {
                step(1, "Sperrbildschirm anzeigen und lange auf eine freie Stelle drücken.")
                step(2, "„Anpassen“ → „Sperrbildschirm“ wählen.")
                step(3, "Auf das Widget-Feld unter der Uhr tippen.")
                step(4, "„Tagesplaner“ auswählen: „Heute“, „Nächster Termin“ oder „Offene Aufgaben“.")
            }
            Section("Home-Bildschirm") {
                step(1, "Lange auf eine freie Stelle des Home-Bildschirms drücken.")
                step(2, "Oben links auf „Bearbeiten“ → „Widget hinzufügen“ tippen.")
                step(3, "„Tagesplaner“ suchen und eine Größe wählen.")
            }
            Section {
                Text("Widgets aktualisieren sich bei jeder Änderung in der App und automatisch zu Beginn und Ende jedes Blocks. iOS legt fest, wie oft Widgets insgesamt neu geladen werden dürfen – in seltenen Fällen kann die Anzeige daher kurz verzögert sein.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle("Widgets")
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Theme.accentFill, in: Circle())
                .foregroundStyle(Theme.accentText)
            Text(text).font(.subheadline)
        }
    }
}
