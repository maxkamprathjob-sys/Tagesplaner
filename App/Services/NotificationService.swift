import Foundation
import UserNotifications
import PlannerCore

/// Lokale Benachrichtigungen (kein Server, kein Push).
/// iOS erlaubt höchstens 64 geplante Benachrichtigungen pro App – wir planen
/// daher nur die nächsten 7 Tage und höchstens 60 Stück.
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "tp-"

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Fragt nach Erlaubnis. Lehnt der Benutzer ab, läuft die App ohne Erinnerungen weiter.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    struct Reminder {
        var id: String
        var title: String
        var body: String
        var fireDate: Date
    }

    /// Plant alle Erinnerungen neu (alte werden vorher entfernt).
    func reschedule(items: [PlanItem], externalEvents: [ExternalEvent], settings: SettingsStore,
                    now: Date, calendar: Calendar) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard settings.notificationsEnabled else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let reminders = NotificationService.makeReminders(items: items, externalEvents: externalEvents,
                                                          leadMinutes: settings.notificationLeadMinutes,
                                                          summaryEnabled: settings.dailySummaryEnabled,
                                                          summaryTime: settings.dailySummaryTime,
                                                          now: now, calendar: calendar)
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: prefix + r.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Reine Funktion – separat testbar.
    static func makeReminders(items: [PlanItem], externalEvents: [ExternalEvent], leadMinutes: Int,
                              summaryEnabled: Bool, summaryTime: TimeOfDay,
                              now: Date, calendar: Calendar, limit: Int = 60) -> [Reminder] {
        let horizon = now.addingTimeInterval(7 * 86_400)
        let lead = TimeInterval(max(0, leadMinutes) * 60)
        var result: [Reminder] = []

        // Tageszusammenfassung zuerst (wichtig, wenige Einträge).
        if summaryEnabled {
            for offset in 0..<7 {
                let day = DayMath.addDays(offset, to: now, calendar: calendar)
                let fire = summaryTime.date(on: day, calendar: calendar)
                guard fire > now else { continue }
                let open = items.filter { $0.isTask && !$0.isDone && calendar.isDate($0.day, inSameDayAs: day) }
                guard !open.isEmpty else { continue }
                let n = open.count
                let what = n == 1 ? "1 offene Aufgabe" : "\(n) offene Aufgaben"
                let names = open.prefix(3).map(\.title).joined(separator: ", ")
                result.append(Reminder(id: "summary-\(WidgetSnapshot.dayKey(day, calendar: calendar))",
                                       title: "Du hast heute noch \(what).",
                                       body: names, fireDate: fire))
            }
        }

        struct Upcoming { var id: String; var title: String; var start: Date; var end: Date; var isSleep: Bool }
        var upcoming: [Upcoming] = items.compactMap { item in
            guard let iv = item.interval, !item.isDone else { return nil }
            return Upcoming(id: item.id.uuidString, title: item.title, start: iv.start, end: iv.end, isSleep: item.isSleep)
        }
        upcoming += externalEvents.filter { !$0.isAllDay }.map {
            Upcoming(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isSleep: false)
        }

        for u in upcoming.sorted(by: { $0.start < $1.start }) {
            let fire = u.start.addingTimeInterval(-lead)
            guard fire > now, u.start <= horizon else { continue }
            let minutesText = leadMinutes == 0 ? "jetzt" : "in \(leadMinutes) Minuten"
            let title = u.isSleep ? "Schlafenszeit \(minutesText)." : "\(u.title) beginnt \(minutesText)."
            result.append(Reminder(id: "item-\(u.id)-\(Int(u.start.timeIntervalSince1970))",
                                   title: title, body: Fmt.range(u.start, u.end), fireDate: fire))
            if result.count >= limit { break }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
