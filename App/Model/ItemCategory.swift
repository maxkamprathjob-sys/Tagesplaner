import Foundation

/// Kategorie eines Eintrags. Bestimmt Symbol und, ob er standardmäßig als fester Termin gilt.
enum ItemCategory: String, CaseIterable, Codable, Identifiable {
    case uni
    case work
    case study
    case sport
    case errand
    case appointment
    case personal
    case sleep
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .uni: return "Universität"
        case .work: return "Arbeit"
        case .study: return "Lernen"
        case .sport: return "Sport"
        case .errand: return "Erledigung"
        case .appointment: return "Termin"
        case .personal: return "Privat"
        case .sleep: return "Schlafen"
        case .other: return "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .uni: return "graduationcap"
        case .work: return "briefcase"
        case .study: return "book"
        case .sport: return "figure.run"
        case .errand: return "cart"
        case .appointment: return "calendar"
        case .personal: return "person"
        case .sleep: return "moon.zzz"
        case .other: return "circle.dashed"
        }
    }

    /// Feste Termine werden von der Planung nie angefasst.
    var isFixedByDefault: Bool {
        switch self {
        case .uni, .work, .appointment, .sleep, .sport: return true
        default: return false
        }
    }

    /// Erkennt eine Kategorie aus dem Titel (lokal, ohne KI).
    static func guess(from title: String) -> ItemCategory {
        let t = title.lowercased()
        let rules: [(ItemCategory, [String])] = [
            (.sleep, ["schlaf", "bett", "nachtruhe"]),
            (.uni, ["uni", "vorlesung", "seminar", "hochschule", "übung", "tutorium", "praktikum"]),
            (.study, ["lernen", "klausur", "prüfung", "hausarbeit", "lesen", "wiederholen", "bauko", "referat"]),
            (.sport, ["sport", "joggen", "laufen", "gym", "fitness", "training", "schwimmen", "rad", "yoga"]),
            (.work, ["arbeit", "job", "schicht", "meeting", "büro", "baustelle"]),
            (.errand, ["einkauf", "einkaufen", "post", "bank", "apotheke", "putzen", "wäsche", "steuer"]),
            (.appointment, ["arzt", "zahnarzt", "termin", "friseur", "amt"])
        ]
        let titleWords = t.split(whereSeparator: { !$0.isLetter }).map(String.init)
        func matches(_ key: String) -> Bool {
            // Kurze Schlüssel nur am Wortanfang ("uni" ≠ "Kommunikation"),
            // lange auch innerhalb von Komposita ("Hausarbeit").
            if titleWords.contains(where: { $0.hasPrefix(key) }) { return true }
            return key.count >= 5 && t.contains(key)
        }
        for (cat, words) in rules where words.contains(where: matches) {
            return cat
        }
        return .other
    }
}
