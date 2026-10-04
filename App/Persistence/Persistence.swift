import Foundation
import SwiftData

/// Dauerhafte, lokale Speicherung mit SwiftData.
/// Die Datenbank liegt im App-Group-Ordner, damit App Intents (Siri/Kurzbefehle)
/// auf dieselben Daten zugreifen. Keine Cloud, kein Konto.
enum Persistence {

    static let schema = Schema([PlanItem.self])

    static var storeURL: URL {
        migrateLocalStoreIntoAppGroupIfNeeded()
        return AppGroup.storageDirectory.appendingPathComponent("Tagesplaner.store")
    }

    /// War die App Group früher nicht verfügbar (z. B. andere Signierung), liegen die Daten
    /// im App-eigenen Ordner. Sobald die App Group verfügbar ist, werden sie einmalig
    /// dorthin kopiert – nie überschrieben, nie gelöscht.
    private static func migrateLocalStoreIntoAppGroupIfNeeded() {
        guard let group = AppGroup.containerURL else { return }
        let fm = FileManager.default
        let local = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let names = ["Tagesplaner.store", "Tagesplaner.store-shm", "Tagesplaner.store-wal"]
        let groupStore = group.appendingPathComponent(names[0])
        let localStore = local.appendingPathComponent(names[0])
        guard !fm.fileExists(atPath: groupStore.path), fm.fileExists(atPath: localStore.path) else { return }
        for name in names {
            let src = local.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: group.appendingPathComponent(name))
            }
        }
    }

    /// Gemeinsamer Container für App und Intents (gleicher Prozess).
    @MainActor
    static let shared: ModelContainer = makeContainer()

    @MainActor
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) -> ModelContainer {
        do {
            let config: ModelConfiguration
            if inMemory {
                config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            } else {
                config = ModelConfiguration(schema: schema, url: url ?? storeURL)
            }
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Notfall: Die App soll nicht abstürzen. Daten der Datei bleiben unangetastet,
            // es wird lediglich eine temporäre Datenbank verwendet und das Problem gemeldet.
            Persistence.lastError = "Die Datenbank konnte nicht geöffnet werden (\(error.localizedDescription)). Deine bisherigen Daten wurden nicht gelöscht."
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    /// Wird in der Oberfläche angezeigt, falls etwas schiefging.
    @MainActor static var lastError: String?
}
