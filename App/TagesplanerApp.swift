import SwiftUI
import SwiftData
import Combine
import PlannerCore

@main
struct TagesplanerApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var calendarService: CalendarService
    @StateObject private var store: PlanStore
    @StateObject private var ui = UIState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = SettingsStore()
        let calendarService = CalendarService()
        let container = Persistence.shared
        let store = PlanStore(context: container.mainContext, settings: settings, calendarService: calendarService)
        if let error = Persistence.lastError { store.errorMessage = error }
        _settings = StateObject(wrappedValue: settings)
        _calendarService = StateObject(wrappedValue: calendarService)
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(calendarService)
                .environmentObject(store)
                .environmentObject(ui)
                .modelContainer(Persistence.shared)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Theme.accent)
                .onReceive(settings.objectWillChange) { _ in
                    store.scheduleIntegrationRefresh()
                }
                .onReceive(calendarService.$revision.dropFirst()) { _ in
                    store.scheduleIntegrationRefresh()
                }
                .onOpenURL { url in ui.handle(url: url, store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            calendarService.refreshStatus()
            ui.refreshToday()
            ui.consumePendingIntent(store: store)
            Task { await store.refreshIntegrations() }
        }
    }
}

/// Zustand der Oberfläche (gewählter Tag, offene Dialoge).
@MainActor
final class UIState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case plan = "Tagesplan"
        case tasks = "Aufgaben"
        var id: String { rawValue }
    }

    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @Published var tab: Tab = .plan
    @Published var showQuickAdd = false
    @Published var editor: EditorRequest?
    @Published var planning: PlanningSession?
    @Published var showSettings = false
    @Published var showPlanDay = false
    @Published var toast: String?
    /// Tag, an dem die App zuletzt aktiv war – für automatischen Wechsel nach Mitternacht.
    private var lastActiveDay = Calendar.current.startOfDay(for: Date())

    func go(to day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
    }

    func shiftDay(_ offset: Int) {
        go(to: Calendar.current.date(byAdding: .day, value: offset, to: selectedDay) ?? selectedDay)
    }

    var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    /// Stand der Benutzer auf "heute" und ist inzwischen ein neuer Tag, springt die Ansicht mit.
    func refreshToday() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != lastActiveDay {
            if selectedDay == lastActiveDay { selectedDay = today }
            lastActiveDay = today
        }
    }

    func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self.toast == text { self.toast = nil }
        }
    }

    /// Öffnet den Planungsdialog für einen Eintrag.
    func startPlanning(_ item: PlanItem, on day: Date? = nil, window: DateInterval? = nil, store: PlanStore) {
        let d = day ?? Calendar.current.startOfDay(for: item.day)
        let target = d < Calendar.current.startOfDay(for: Date()) ? Calendar.current.startOfDay(for: Date()) : d
        planning = PlanningSession(itemID: item.id, day: target, window: window,
                                   result: store.suggestion(for: item, on: target, within: window))
    }

    func handle(url: URL, store: PlanStore) {
        // tagesplaner://day/2026-10-28 oder tagesplaner://today (aus Widgets)
        guard url.scheme == "tagesplaner" else { return }
        if url.host == "day", let key = url.pathComponents.dropFirst().first {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3, let d = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
                go(to: d)
            }
        } else {
            go(to: Date())
        }
        if url.host == "tasks" { tab = .tasks }
    }

    /// Von Siri/Kurzbefehle angelegte Aufgabe → Vorschlag anzeigen.
    func consumePendingIntent(store: PlanStore) {
        let defaults = AppGroup.defaults
        guard let raw = defaults.string(forKey: PendingIntent.key) else { return }
        defaults.removeObject(forKey: PendingIntent.key)
        guard let id = UUID(uuidString: raw), let item = store.item(id: id) else { return }
        go(to: item.day)
        startPlanning(item, store: store)
    }
}

enum PendingIntent {
    static let key = "pendingPlanItemID"
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var item: PlanItem?
    /// Vorbelegung für neue Einträge.
    var defaultStart: Date?
    var defaultDay: Date
    var asTask: Bool
}

struct PlanningSession: Identifiable {
    let id = UUID()
    var itemID: UUID
    var day: Date
    var window: DateInterval?
    var result: SchedulingResult
    var candidateIndex = 0
}
