import Foundation
import SwiftData

/// Dauerhafte, lokale Speicherung mit SwiftData.
/// Die Datenbank liegt im App-Group-Ordner, damit App Intents (Siri/Kurzbefehle)
/// auf dieselben Daten zugreifen. Keine Cloud, kein Konto.
enum Persistence {

    static let schema = Schema([PlanItem.self])

    static var storeURL: URL {
        AppGroup.storageDirectory.appendingPathComponent("Tagesplaner.store")
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
