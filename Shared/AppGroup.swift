import Foundation

/// Gemeinsamer Speicherbereich von App, Widgets und Live Activity.
///
/// Die Kennung wird zur Laufzeit ermittelt – in dieser Reihenfolge:
/// 1. aus dem eingebetteten Provisioning-Profil (die tatsächlich signierte App Group;
///    wichtig, wenn Sideloading-Tools die Kennungen beim Signieren umbenennen),
/// 2. aus der Info.plist (beim Build aus BUNDLE_ID_PREFIX erzeugt),
/// 3. Platzhalter.
enum AppGroup {
    static let identifier: String = {
        let candidates = provisionedGroups() + [infoPlistGroup()].compactMap { $0 }
        // Erste Gruppe, für die iOS tatsächlich einen Ordner liefert.
        for group in candidates where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil {
            return group
        }
        return candidates.first ?? "group.tagesplaner"
    }()

    /// nil, wenn die App Group nicht verfügbar ist (z. B. Signierung ohne App Group).
    /// Aufrufer weichen dann auf den App-eigenen Speicher aus.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isAvailable: Bool { containerURL != nil }

    static var defaults: UserDefaults {
        if isAvailable, let d = UserDefaults(suiteName: identifier) { return d }
        return .standard
    }

    /// Ablageordner: App Group, sonst Application Support der App.
    static var storageDirectory: URL {
        if let url = containerURL {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    private static func infoPlistGroup() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    }

    /// Liest die App Groups aus embedded.mobileprovision (signierte Plist innerhalb einer CMS-Hülle).
    private static func provisionedGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            return []
        }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return []
        }
        return groups.filter { !$0.contains("*") }
    }
}
