import Foundation
import SwiftUI
import PlannerCore

/// Persönliche Einstellungen. Lokal gespeichert (UserDefaults der App Group).
@MainActor
final class SettingsStore: ObservableObject {

    enum Appearance: String, CaseIterable, Identifiable {
        case dark, light, system
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dark: return "Dunkel"
            case .light: return "Hell"
            case .system: return "System"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .dark: return .dark
            case .light: return .light
            case .system: return nil
            }
        }
    }

    private let defaults: UserDefaults

    @Published var wakeTime: TimeOfDay { didSet { save() } }
    @Published var bedtime: TimeOfDay { didSet { save() } }
    @Published var bufferMinutes: Int { didSet { save() } }
    @Published var defaultTaskMinutes: Int { didSet { save() } }

    @Published var notificationsEnabled: Bool { didSet { save() } }
    @Published var notificationLeadMinutes: Int { didSet { save() } }
    @Published var dailySummaryEnabled: Bool { didSet { save() } }
    @Published var dailySummaryTime: TimeOfDay { didSet { save() } }

    @Published var calendarEnabled: Bool { didSet { save() } }
    @Published var liveActivityEnabled: Bool { didSet { save() } }
    @Published var appearance: Appearance { didSet { save() } }

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        wakeTime = TimeOfDay(minutesSinceMidnight: defaults.object(forKey: "wake") as? Int ?? 7 * 60)
        bedtime = TimeOfDay(minutesSinceMidnight: defaults.object(forKey: "bed") as? Int ?? 21 * 60)
        bufferMinutes = defaults.object(forKey: "buffer") as? Int ?? 10
        defaultTaskMinutes = defaults.object(forKey: "defaultTask") as? Int ?? 60
        notificationsEnabled = defaults.bool(forKey: "notify")
        notificationLeadMinutes = defaults.object(forKey: "notifyLead") as? Int ?? 15
        dailySummaryEnabled = defaults.object(forKey: "summary") as? Bool ?? true
        dailySummaryTime = TimeOfDay(minutesSinceMidnight: defaults.object(forKey: "summaryTime") as? Int ?? 8 * 60)
        calendarEnabled = defaults.bool(forKey: "calendar")
        liveActivityEnabled = defaults.object(forKey: "liveActivity") as? Bool ?? true
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .dark
    }

    var planner: PlannerSettings {
        PlannerSettings(wakeTime: wakeTime, bedtime: bedtime, bufferMinutes: bufferMinutes,
                        minimumSlotMinutes: 15, gridMinutes: 5)
    }

    private func save() {
        defaults.set(wakeTime.minutesSinceMidnight, forKey: "wake")
        defaults.set(bedtime.minutesSinceMidnight, forKey: "bed")
        defaults.set(bufferMinutes, forKey: "buffer")
        defaults.set(defaultTaskMinutes, forKey: "defaultTask")
        defaults.set(notificationsEnabled, forKey: "notify")
        defaults.set(notificationLeadMinutes, forKey: "notifyLead")
        defaults.set(dailySummaryEnabled, forKey: "summary")
        defaults.set(dailySummaryTime.minutesSinceMidnight, forKey: "summaryTime")
        defaults.set(calendarEnabled, forKey: "calendar")
        defaults.set(liveActivityEnabled, forKey: "liveActivity")
        defaults.set(appearance.rawValue, forKey: "appearance")
    }
}

extension TimeOfDay {
    /// Brücke zu DatePicker (der ein Date braucht).
    func asDate(on day: Date = Date()) -> Date {
        date(on: day, calendar: Calendar.current)
    }

    init(_ date: Date) {
        self.init(date: date, calendar: Calendar.current)
    }
}
