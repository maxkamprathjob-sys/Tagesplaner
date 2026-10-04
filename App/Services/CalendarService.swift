import Foundation
import EventKit

/// Ein Termin aus dem Apple-Kalender. Wird nur gelesen und nie gespeichert oder verändert.
struct ExternalEvent: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarName: String

    var interval: DateInterval { DateInterval(start: start, end: max(end, start)) }
}

/// Lesender Zugriff auf den Apple-Kalender (EventKit).
/// - Fragt erst nach Erlaubnis, wenn der Benutzer die Integration einschaltet.
/// - Ohne Erlaubnis funktioniert die App normal weiter.
/// - Schreibt NIE in den Kalender.
@MainActor
final class CalendarService: ObservableObject {
    private let store = EKEventStore()
    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// Erhöht sich, wenn sich der Apple-Kalender ändert.
    @Published private(set) var revision = 0
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.revision += 1 }
        }
    }

    var hasAccess: Bool { status == .fullAccess }

    var statusText: String {
        switch status {
        case .fullAccess: return "Zugriff erlaubt"
        case .denied: return "Zugriff verweigert – in den iOS-Einstellungen änderbar"
        case .restricted: return "Zugriff durch iOS eingeschränkt"
        case .writeOnly: return "Nur Schreibzugriff – zum Anzeigen wird voller Zugriff benötigt"
        case .notDetermined: return "Noch nicht gefragt"
        @unknown default: return "Unbekannt"
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            status = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
    }

    /// Termine, die das Intervall berühren. Liefert [] ohne Berechtigung.
    func events(in interval: DateInterval) -> [ExternalEvent] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            let key = (event.eventIdentifier ?? UUID().uuidString) + "@" + String(start.timeIntervalSince1970)
            return ExternalEvent(id: "ek-" + key,
                                 title: event.title?.isEmpty == false ? event.title! : "Termin",
                                 start: start, end: end,
                                 isAllDay: event.isAllDay,
                                 calendarName: event.calendar?.title ?? "Kalender")
        }
        .sorted { $0.start < $1.start }
    }
}
