import SwiftUI
import UIKit

/// Farbwelt: Schwarz, Weiß, dunkles Lila. Wenige Farben, hoher Kontrast.
enum Theme {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Hintergrund: echtes Schwarz im Dark Mode (OLED), Weiß im Light Mode.
    static let background = dynamic(light: 0xFFFFFF, dark: 0x000000)
    /// Flächen (Karten, Zeitblöcke).
    static let surface = dynamic(light: 0xF3F1F7, dark: 0x141218)
    static let surfaceStrong = dynamic(light: 0xE6E1F0, dark: 0x1F1B27)
    /// Haarlinien der Zeitleiste.
    static let hairline = dynamic(light: 0xDDD8E6, dark: 0x2A2533)
    static let textPrimary = dynamic(light: 0x0B0910, dark: 0xF5F3FA)
    static let textSecondary = dynamic(light: 0x5E5869, dark: 0x9C95AB)

    /// Dunkles Lila – Akzent, Flächen.
    static let accent = dynamic(light: 0x4B2496, dark: 0x7C4DDB)
    /// Helles Lila für Text/Linien auf Schwarz.
    static let accentText = dynamic(light: 0x4B2496, dark: 0xC4AEFF)
    static let accentFill = dynamic(light: 0xE9E0FB, dark: 0x2A1950)

    /// Einzige Signalfarbe: Konflikte und gefährdete Deadlines.
    static let warning = dynamic(light: 0xC2263A, dark: 0xFF5C6E)
}

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

/// Formatierung, die App und Widgets gemeinsam nutzen.
enum Fmt {
    static func time(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func range(_ start: Date, _ end: Date) -> String {
        "\(time(start))–\(time(end))"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.setLocalizedDateFormatFromTemplate("EEEdM")
        return f
    }()

    /// "Mittwoch, 28. Oktober"
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    /// "Mi., 28.10."
    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }

    /// "Heute", "Morgen", "Gestern" oder nil
    static func relativeDayName(_ date: Date, now: Date = Date()) -> String? {
        let cal = Calendar.current
        let d = cal.startOfDay(for: date)
        let t = cal.startOfDay(for: now)
        let diff = cal.dateComponents([.day], from: t, to: d).day ?? 99
        switch diff {
        case 0: return "Heute"
        case 1: return "Morgen"
        case -1: return "Gestern"
        case 2: return "Übermorgen"
        default: return nil
        }
    }
}
