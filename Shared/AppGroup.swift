import Foundation

/// Gemeinsamer Speicherbereich von App, Widgets und Live Activity.
/// Die Kennung wird beim Build aus BUNDLE_ID_PREFIX erzeugt und steht in der Info.plist.
enum AppGroup {
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String) ?? "group.tagesplaner"
    }

    /// nil, wenn die App Group nicht verfügbar ist (z. B. fehlerhaftes Signing).
    /// Aufrufer müssen dann auf den App-eigenen Speicher ausweichen.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
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
}
