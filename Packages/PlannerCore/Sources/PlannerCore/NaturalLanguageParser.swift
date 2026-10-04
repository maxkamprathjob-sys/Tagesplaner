import Foundation

/// Strukturiertes Ergebnis einer deutschen Freitexteingabe.
public struct ParsedInput: Equatable, Sendable {
    public var title: String
    /// Tag, auf den sich der Eintrag bezieht (Tagesbeginn). nil = nicht genannt.
    public var day: Date?
    public var startTime: TimeOfDay?
    public var endTime: TimeOfDay?
    public var durationMinutes: Int?
    public var deadline: Date?
    public var priority: Priority?
    public var isSleep: Bool
    /// "zwischen Uni und Sport" → after = "uni", before = "sport"
    public var afterItem: String?
    public var beforeItem: String?

    public init(title: String, day: Date? = nil, startTime: TimeOfDay? = nil, endTime: TimeOfDay? = nil,
                durationMinutes: Int? = nil, deadline: Date? = nil, priority: Priority? = nil,
                isSleep: Bool = false, afterItem: String? = nil, beforeItem: String? = nil) {
        self.title = title
        self.day = day
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.deadline = deadline
        self.priority = priority
        self.isSleep = isSleep
        self.afterItem = afterItem
        self.beforeItem = beforeItem
    }

    /// Feste Uhrzeit vorhanden → direkt als Zeitblock anlegbar.
    public var hasFixedTime: Bool { startTime != nil }

    /// Zeitraum, falls Start (und Ende oder Dauer) bekannt sind.
    /// Ende vor Start ergibt automatisch einen Übernacht-Block.
    public func interval(defaultDay: Date, calendar: Calendar) -> DateInterval? {
        guard let start = startTime else { return nil }
        let d = day ?? defaultDay
        if let end = endTime {
            return DayMath.interval(on: d, from: start, to: end, calendar: calendar)
        }
        if let minutes = durationMinutes {
            let s = start.date(on: d, calendar: calendar)
            return DateInterval(start: s, duration: TimeInterval(minutes * 60))
        }
        return nil
    }
}

/// Regelbasierter, lokaler Parser für deutsche Eingaben.
/// Beispiele: "Ich muss morgen 2 Stunden lernen", "Ich habe morgen um 8 Uhr Uni bis 14 Uhr",
/// "Um 21 Uhr möchte ich schlafen", "Plane mir 90 Minuten Sport ein",
/// "Hausarbeit bis 30.10. 18 Uhr, 2 Stunden, wichtig".
/// Es werden keine Daten an externe Dienste gesendet.
public struct NaturalLanguageParser: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func parse(_ input: String, now: Date) -> ParsedInput {
        let s = TextScanner(input)
        let today = calendar.startOfDay(for: now)

        // 1. Priorität
        var priority: Priority? = nil
        if s.take(#"\b(?:sehr|extrem|super|total)\s+wichtig\b|\bdringend\b|!!!"#) != nil {
            priority = .veryHigh
        } else if s.take(#"\bnicht\s+wichtig\b|\bunwichtig\b|\bniedrige\s+priorität\b"#) != nil {
            priority = .low
        } else if s.take(#"\bwichtig\b|\bhohe\s+priorität\b|!!"#) != nil {
            priority = .high
        }

        // 2. Deadline-Schlüsselwort
        var deadlineMarker = s.take(#"\b(?:deadline|fällig(?:\s+am)?|abgabe(?:\s+am)?|spätestens)\b:?"#) != nil

        // 3. Datum: "29.10.", "am 29.10.2026", "bis 30.10."
        var day: Date? = nil
        var dayIsDeadline = false
        if let g = s.take(#"(?:\b(bis)\s+(?:zum\s+|spätestens\s+)?|\bam\s+|\bden\s+)?\b(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})?"#) {
            if let d = resolveDate(day: g[2], month: g[3], year: g[4], today: today) {
                day = d
                dayIsDeadline = g[1] != nil || deadlineMarker
            }
        }

        // 4. Relative Tage / Wochentage
        if day == nil {
            if let g = s.take(#"(?:\b(bis)\s+(?:spätestens\s+)?)?\b(übermorgen|morgen|heute|gestern)\b"#) {
                let offset: Int
                switch g[2]?.lowercased() {
                case "übermorgen": offset = 2
                case "morgen": offset = 1
                case "gestern": offset = -1
                default: offset = 0
                }
                day = DayMath.addDays(offset, to: today, calendar: calendar)
                dayIsDeadline = g[1] != nil || deadlineMarker
            } else if let g = s.take(#"(?:\b(bis)\s+(?:spätestens\s+)?)?(?:\b(?:am|nächsten|nächster|kommenden|diesen)\s+)?\b(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\b"#) {
                let isDeadline = g[1] != nil || deadlineMarker
                if let name = g[2], let d = resolveWeekday(name, today: today, allowToday: isDeadline) {
                    day = d
                    dayIsDeadline = isDeadline
                }
            }
        }

        // 5. Dauer
        var duration = 0
        if s.take(#"\b(?:eine\s+)?halbe\s+stunde\b"#) != nil { duration += 30 }
        if s.take(#"\bdreiviertel\s*stunden?\b"#) != nil { duration += 45 }
        if s.take(#"\b(?:anderthalb|eineinhalb)\s+stunden?\b"#) != nil { duration += 90 }
        for _ in 0..<3 {
            guard let g = s.take(#"\b(\d+(?:[.,]\d+)?|einer|einen|eine|ein|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|elf|zwölf)\s*(stunden|stunde|std\.?|h|minuten|minute|min\.?)(?![\wäöüß])"#),
                  let numText = g[1], let unit = g[2]?.lowercased() else { break }
            guard let value = number(numText) else { continue }
            let isHours = unit.hasPrefix("st") || unit == "h"
            duration += Int((value * (isHours ? 60 : 1)).rounded())
        }

        // 6. Tageszeit-Hinweise
        var pm = false
        if s.take(#"\b(?:abends|am\s+abend|abend|nachmittags|am\s+nachmittag|nachts)\b"#) != nil { pm = true }
        _ = s.take(#"\b(?:morgens|vormittags|früh|am\s+morgen|am\s+vormittag)\b"#)

        // 7. Uhrzeiten
        var start: TimeOfDay? = nil
        var end: TimeOfDay? = nil
        var bisTime: TimeOfDay? = nil

        // 7a. Zeitraum: "von 8 bis 14 Uhr", "8-14 Uhr", "08:00–14:00", "zwischen 17 und 19 Uhr"
        for m in s.allMatches(#"\b(von|ab|zwischen)?\s*(\d{1,2})(?:[:.](\d{2}))?\s*(uhr)?\s*(bis|-|und)\s*(\d{1,2})(?:[:.](\d{2}))?\s*(uhr)?"#) {
            let g = m.groups
            let prefix = g[1]?.lowercased()
            let sep = g[5]?.lowercased()
            let hasColon = g[3] != nil || g[7] != nil
            let hasUhr = g[4] != nil || g[8] != nil
            if sep == "und" && prefix != "zwischen" { continue }
            guard prefix != nil || hasColon || hasUhr else { continue }
            guard let t1 = time(g[2], g[3], pm: pm), let t2 = time(g[6], g[7], pm: pm) else { continue }
            start = t1
            end = t2
            s.blank(m.range)
            break
        }

        // 7b. "bis 14 Uhr" – Ende (falls Start vorhanden) oder Deadline
        if start == nil || end == nil {
            if let g = s.take(#"\bbis\s+(?:spätestens\s+)?(?:um\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*(uhr)?"#),
               g[2] != nil || g[3] != nil {
                bisTime = time(g[1], g[2], pm: pm)
            }
        }

        // 7c. Startzeit: "um 8 Uhr", "ab 14:30", "14:52", "20 Uhr"
        if start == nil {
            if let g = s.take(#"\b(?:um|ab|gegen)\s+(\d{1,2})(?:[:.](\d{2}))?(?:\s*uhr)?\b"#) {
                start = time(g[1], g[2], pm: pm)
            } else if let g = s.take(#"\b(\d{1,2}):(\d{2})(?:\s*uhr)?"#) {
                start = time(g[1], g[2], pm: pm)
            } else if let g = s.take(#"\b(\d{1,2})(?:\.(\d{2}))?\s*uhr\b"#) {
                start = time(g[1], g[2], pm: pm)
            }
        }

        var deadline: Date? = nil
        if let bt = bisTime {
            if start != nil && end == nil && !dayIsDeadline && !deadlineMarker {
                end = bt
            } else {
                let base = (dayIsDeadline ? day : nil) ?? day ?? today
                deadline = bt.date(on: base, calendar: calendar)
                deadlineMarker = true
            }
        }
        if dayIsDeadline, let d = day {
            if deadline == nil {
                if let st = start, end == nil {
                    // "Deadline 30.10. 18:00" → Uhrzeit gehört zur Deadline
                    deadline = st.date(on: d, calendar: calendar)
                    start = nil
                } else {
                    deadline = TimeOfDay(hour: 23, minute: 59).date(on: d, calendar: calendar)
                }
            }
            day = nil
        }

        // 8. Bezug auf andere Einträge: "zwischen Uni und Sport", "nach der Uni"
        var afterItem: String? = nil
        var beforeItem: String? = nil
        let article = #"(?:(?:der|dem|den|die|das)\s+)?"#
        if let g = s.take(#"\bzwischen\s+"# + article + #"([^\s\d,.]+)\s+und\s+"# + article + #"([^\s\d,.]+)"#) {
            afterItem = g[1]?.lowercased()
            beforeItem = g[2]?.lowercased()
        } else {
            if let g = s.take(#"\bnach\s+(?:der|dem|den)\s+([^\s\d,.]+)"#) { afterItem = g[1]?.lowercased() }
            if let g = s.take(#"\bvor\s+(?:der|dem|den)\s+([^\s\d,.]+)"#) { beforeItem = g[1]?.lowercased() }
        }

        // 9. Schlaf
        let isSleep = s.matches(#"\b(?:schlafen|schlaf|ins\s+bett|pennen|nachtruhe)\b"#)

        // 10. Titel aus dem Rest
        var title = cleanTitle(s.remainder)
        if isSleep && (title.isEmpty || title.lowercased().contains("schlaf") || title.lowercased().contains("bett")) {
            title = "Schlafen"
        }
        if title.isEmpty { title = "Neuer Eintrag" }

        return ParsedInput(title: title, day: day, startTime: start, endTime: end,
                           durationMinutes: duration > 0 ? duration : nil,
                           deadline: deadline, priority: priority, isSleep: isSleep,
                           afterItem: afterItem, beforeItem: beforeItem)
    }

    // MARK: - Hilfen

    private func time(_ hourText: String?, _ minuteText: String?, pm: Bool) -> TimeOfDay? {
        guard let ht = hourText, var h = Int(ht) else { return nil }
        let m = minuteText.flatMap { Int($0) } ?? 0
        guard (0...24).contains(h), (0...59).contains(m) else { return nil }
        if h == 24 && m > 0 { return nil }
        if pm && h >= 1 && h <= 11 { h += 12 }
        return TimeOfDay(hour: h == 24 ? 0 : h, minute: m)
    }

    private func number(_ text: String) -> Double? {
        let t = text.lowercased().replacingOccurrences(of: ",", with: ".")
        if let v = Double(t) { return v }
        let words: [String: Double] = [
            "ein": 1, "eine": 1, "einen": 1, "einer": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5,
            "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12
        ]
        return words[t]
    }

    private func resolveDate(day: String?, month: String?, year: String?, today: Date) -> Date? {
        guard let dText = day, let d = Int(dText), let mText = month, let m = Int(mText),
              (1...31).contains(d), (1...12).contains(m) else { return nil }
        var comps = DateComponents()
        comps.day = d
        comps.month = m
        let currentYear = calendar.component(.year, from: today)
        if let yText = year, var y = Int(yText) {
            if y < 100 { y += 2000 }
            comps.year = y
            return validDate(comps)
        }
        comps.year = currentYear
        guard let candidate = validDate(comps) else { return nil }
        // Ohne Jahr: liegt das Datum mehr als 60 Tage zurück, ist das nächste Jahr gemeint.
        if candidate < DayMath.addDays(-60, to: today, calendar: calendar) {
            comps.year = currentYear + 1
            return validDate(comps)
        }
        return candidate
    }

    private func validDate(_ comps: DateComponents) -> Date? {
        guard let date = calendar.date(from: comps) else { return nil }
        // Ungültige Daten wie 31.02. ablehnen statt still umzurechnen.
        let check = calendar.dateComponents([.day, .month], from: date)
        guard check.day == comps.day, check.month == comps.month else { return nil }
        return calendar.startOfDay(for: date)
    }

    private func resolveWeekday(_ name: String, today: Date, allowToday: Bool) -> Date? {
        let map = ["sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4,
                   "donnerstag": 5, "freitag": 6, "samstag": 7]
        guard let target = map[name.lowercased()] else { return nil }
        let current = calendar.component(.weekday, from: today)
        var diff = (target - current + 7) % 7
        if diff == 0 && !allowToday { diff = 7 }
        return DayMath.addDays(diff, to: today, calendar: calendar)
    }

    private func cleanTitle(_ raw: String) -> String {
        var words = raw
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)).isEmpty }

        // Füllwörter überall entfernen
        let anywhere: Set<String> = ["ich", "muss", "musst", "müsste", "habe", "hab", "möchte", "will",
                                     "würde", "gern", "gerne", "noch", "bitte", "mal", "irgendwo",
                                     "irgendwann", "plane", "plan", "pack", "packe", "mir", "einplanen",
                                     "eintragen", "trag", "trage", "uhr", "dauer", "dauert", "ca", "circa",
                                     "etwa", "ungefähr"]
        words = words.filter { !anywhere.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }

        // Am Anfang/Ende entfernen
        let edge: Set<String> = ["und", "um", "am", "von", "bis", "ein", "eine", "einen", "für", "die",
                                 "der", "das", "den", "dem", "zu", "mit", "auch", "dann", "ab", "es"]
        while let first = words.first, edge.contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, edge.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            words.removeLast()
        }

        var title = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }
        return title
    }
}

// MARK: - TextScanner

/// Findet Muster und "verbraucht" sie, indem die Fundstelle durch Leerzeichen
/// gleicher Länge ersetzt wird. So bleiben spätere Positionen gültig und der
/// unverbrauchte Rest ergibt den Titel.
final class TextScanner {
    private let text: NSMutableString

    init(_ input: String) {
        let normalized = input
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        text = NSMutableString(string: normalized)
    }

    var remainder: String { text as String }

    struct Match {
        var range: NSRange
        var groups: [String?]
    }

    private func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    func allMatches(_ pattern: String) -> [Match] {
        guard let re = regex(pattern) else { return [] }
        let str = text as String
        let ns = text as NSString
        return re.matches(in: str, range: NSRange(location: 0, length: ns.length)).map { r in
            var groups: [String?] = []
            for i in 0..<r.numberOfRanges {
                let gr = r.range(at: i)
                groups.append(gr.location == NSNotFound ? nil : ns.substring(with: gr))
            }
            return Match(range: r.range, groups: groups)
        }
    }

    /// Erste Fundstelle; Gruppe 0 = gesamter Treffer. Die Fundstelle wird verbraucht.
    func take(_ pattern: String) -> [String?]? {
        guard let m = allMatches(pattern).first else { return nil }
        blank(m.range)
        return m.groups
    }

    func matches(_ pattern: String) -> Bool {
        !allMatches(pattern).isEmpty
    }

    func blank(_ range: NSRange) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        text.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
    }
}
