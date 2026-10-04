import Foundation

/// Uhrzeit ohne Datum (z. B. Schlafenszeit 21:00).
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        let total = TimeOfDay.normalize(hour * 60 + minute)
        self.hour = total / 60
        self.minute = total % 60
    }

    public init(minutesSinceMidnight: Int) {
        let total = TimeOfDay.normalize(minutesSinceMidnight)
        self.hour = total / 60
        self.minute = total % 60
    }

    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    /// "08:05"
    public var formatted: String { String(format: "%02d:%02d", hour, minute) }

    /// Konkreter Zeitpunkt an einem Tag. Robust gegenüber Zeitumstellung,
    /// weil vom Tagesbeginn aus gerechnet wird.
    public func date(on day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        if let d = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) {
            return d
        }
        // Fällt die Uhrzeit in eine Zeitumstellungs-Lücke, nehmen wir die nächste gültige Zeit.
        return start.addingTimeInterval(TimeInterval(minutesSinceMidnight * 60))
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    private static func normalize(_ minutes: Int) -> Int {
        let m = minutes % (24 * 60)
        return m < 0 ? m + 24 * 60 : m
    }
}

/// Datums- und Intervallhilfen. Alle Funktionen sind rein und testbar.
public enum DayMath {

    /// Standardkalender der App: gregorianisch, Woche beginnt Montag, aktuelle Zeitzone.
    public static var plannerCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "de_DE")
        cal.timeZone = TimeZone.current
        cal.firstWeekday = 2
        return cal
    }

    public static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func addDays(_ days: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(TimeInterval(days * 86_400))
    }

    /// Der Kalendertag als Intervall [00:00, 00:00 des Folgetags).
    /// Berücksichtigt 23- und 25-Stunden-Tage bei Zeitumstellung.
    public static func dayInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = addDays(1, to: start, calendar: calendar)
        return DateInterval(start: start, end: end)
    }

    /// Erzeugt ein Intervall aus zwei Uhrzeiten an einem Tag.
    /// Liegt das Ende vor oder auf dem Start (z. B. 21:00–07:00), endet es am Folgetag.
    public static func interval(on day: Date, from start: TimeOfDay, to end: TimeOfDay,
                                calendar: Calendar) -> DateInterval {
        let s = start.date(on: day, calendar: calendar)
        var e = end.date(on: day, calendar: calendar)
        if e <= s {
            e = end.date(on: addDays(1, to: day, calendar: calendar), calendar: calendar)
        }
        return DateInterval(start: s, end: e)
    }

    /// Korrigiert ein vom Benutzer eingegebenes Start/Ende-Paar:
    /// Liegt das Ende vor dem Start, wird es auf den Folgetag gelegt (Übernacht-Block).
    /// Gibt nil zurück, wenn Start und Ende identisch sind.
    public static func normalizedInterval(start: Date, end: Date, calendar: Calendar) -> DateInterval? {
        if end > start { return DateInterval(start: start, end: end) }
        if end == start { return nil }
        // Ende liegt vor dem Start → gleiche Uhrzeit am Tag nach dem Start.
        let endTime = TimeOfDay(date: end, calendar: calendar)
        let startTime = TimeOfDay(date: start, calendar: calendar)
        let fixed = interval(on: start, from: startTime, to: endTime, calendar: calendar)
        return DateInterval(start: start, end: fixed.end)
    }

    /// Echte Überschneidung. Aneinandergrenzende Intervalle (14:00–15:00, 15:00–16:00)
    /// überschneiden sich NICHT – anders als `DateInterval.intersects`.
    public static func overlaps(_ a: DateInterval, _ b: DateInterval) -> Bool {
        a.start < b.end && b.start < a.end
    }

    public static func intersection(_ a: DateInterval, _ b: DateInterval) -> DateInterval? {
        let s = max(a.start, b.start)
        let e = min(a.end, b.end)
        return s < e ? DateInterval(start: s, end: e) : nil
    }

    public static func minutes(_ interval: DateInterval) -> Int {
        Int((interval.duration / 60).rounded())
    }

    /// Rundet einen Zeitpunkt auf das nächste Raster (Standard 5 Minuten) auf.
    public static func roundUp(_ date: Date, toMinutes step: Int, calendar: Calendar) -> Date {
        guard step > 0 else { return date }
        let dayStart = calendar.startOfDay(for: date)
        let seconds = date.timeIntervalSince(dayStart)
        let stepSeconds = Double(step * 60)
        let rounded = ((seconds - 0.001) / stepSeconds).rounded(.up) * stepSeconds
        return dayStart.addingTimeInterval(max(0, rounded))
    }

    /// Fasst überlappende/angrenzende Intervalle zusammen (sortiert).
    public static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for i in sorted {
            if let last = result.last, i.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, i.end))
            } else {
                result.append(i)
            }
        }
        return result
    }

    /// Zieht belegte Intervalle von einem Fenster ab.
    public static func subtract(_ busy: [DateInterval], from window: DateInterval) -> [DateInterval] {
        var free: [DateInterval] = []
        var cursor = window.start
        for b in merge(busy) {
            if b.end <= cursor { continue }
            if b.start >= window.end { break }
            if b.start > cursor {
                free.append(DateInterval(start: cursor, end: min(b.start, window.end)))
            }
            cursor = max(cursor, b.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end {
            free.append(DateInterval(start: cursor, end: window.end))
        }
        return free
    }
}

/// Deutsche Formatierung von Dauern ohne falsche Genauigkeit.
public enum DurationText {

    /// Exakt: "2 Std. 15 Min.", "45 Min.", "3 Std."
    public static func exact(_ minutes: Int) -> String {
        let m = max(0, minutes)
        let h = m / 60
        let r = m % 60
        if h == 0 { return "\(r) Min." }
        if r == 0 { return "\(h) Std." }
        return "\(h) Std. \(r) Min."
    }

    /// Grob gerundet für Einschätzungen: unter 2 Std. auf 15 Min., darüber auf 30 Min.
    public static func approximate(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m == 0 { return "0 Min." }
        if m < 15 { return "wenige Min." }
        let step = m < 120 ? 15 : 30
        let rounded = Int((Double(m) / Double(step)).rounded()) * step
        if rounded < 60 { return "\(rounded) Min." }
        let h = rounded / 60
        let r = rounded % 60
        if r == 0 { return "\(h) Std." }
        if r == 30 { return "\(h),5 Std." }
        return "\(h) Std. \(r) Min."
    }

    public static func range(_ interval: DateInterval, calendar: Calendar) -> String {
        let s = TimeOfDay(date: interval.start, calendar: calendar).formatted
        let e = TimeOfDay(date: interval.end, calendar: calendar).formatted
        return "\(s)–\(e)"
    }
}
