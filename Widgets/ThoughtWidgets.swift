import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Ordnerauswahl für das Widget

struct ThoughtFolderEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ordner"
    static var defaultQuery = ThoughtFolderQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ThoughtFolderQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ThoughtFolderEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ThoughtFolderEntity] {
        all()
    }

    private func all() -> [ThoughtFolderEntity] {
        (ThoughtsSnapshotStore.read()?.folders ?? []).map { ThoughtFolderEntity(id: $0.id, name: $0.name) }
    }
}

struct ThoughtsWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Gedanken"
    static var description = IntentDescription("Zeigt deine letzten Gedanken – alle oder aus einem Ordner.")

    @Parameter(title: "Ordner")
    var folder: ThoughtFolderEntity?
}

// MARK: - Timeline

struct ThoughtsEntry: TimelineEntry {
    let date: Date
    let snapshot: ThoughtsSnapshot?
    let folderID: String?
}

struct ThoughtsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ThoughtsEntry {
        ThoughtsEntry(date: Date(), snapshot: nil, folderID: nil)
    }

    func snapshot(for configuration: ThoughtsWidgetIntent, in context: Context) async -> ThoughtsEntry {
        ThoughtsEntry(date: Date(), snapshot: ThoughtsSnapshotStore.read(), folderID: configuration.folder?.id)
    }

    func timeline(for configuration: ThoughtsWidgetIntent, in context: Context) async -> Timeline<ThoughtsEntry> {
        // Die App lädt das Widget bei jeder Änderung neu; zusätzlich stündlich.
        let entry = ThoughtsEntry(date: Date(), snapshot: ThoughtsSnapshotStore.read(), folderID: configuration.folder?.id)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
    }
}

// MARK: - Widget "Gedanken"

struct ThoughtsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ThoughtsWidget", intent: ThoughtsWidgetIntent.self, provider: ThoughtsProvider()) { entry in
            ThoughtsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
                .widgetURL(URL(string: "tagesplaner://thoughts"))
        }
        .configurationDisplayName("Gedanken")
        .description("Deine letzten Gedanken. Lange drücken → „Widget bearbeiten“, um einen Ordner zu wählen.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular,
                            .systemSmall, .systemMedium, .systemLarge])
    }
}

struct ThoughtsWidgetView: View {
    let entry: ThoughtsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let folder = entry.snapshot?.folder(id: entry.folderID)
        let items = entry.snapshot?.items(inFolder: entry.folderID) ?? []
        let title = (folder?.name ?? "Gedanken").uppercased()
        let symbol = folder?.symbol ?? "brain.head.profile"

        switch family {
        case .accessoryInline:
            if let first = items.first {
                Label(first.text, systemImage: symbol)
            } else {
                Label("Keine Gedanken", systemImage: symbol)
            }

        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text("\(items.count)").font(.system(size: 20, weight: .bold))
            }
            .widgetAccentable()

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                    Text("\(title) · \(items.count)")
                }
                .font(.system(size: 11, weight: .bold))
                .widgetAccentable()
                if items.isEmpty {
                    Text(entry.snapshot == nil ? "App einmal öffnen" : "Nichts offen")
                        .font(.system(size: 13))
                } else {
                    ForEach(items.prefix(3)) { item in
                        Text("• \(item.text)").font(.system(size: 12)).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            let limit = family == .systemSmall ? 4 : (family == .systemMedium ? 4 : 10)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.accentText)
                    Spacer()
                    Text("\(items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if items.isEmpty {
                    Text(entry.snapshot == nil ? "Öffne die App einmal, um das Widget zu füllen." : "Keine Gedanken.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(items.prefix(limit)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if entry.folderID == nil && family != .systemSmall {
                            Image(systemName: item.symbol)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.accentText)
                                .frame(width: 14)
                        }
                        Text(item.text)
                            .font(.system(size: family == .systemSmall ? 12 : 13))
                            .lineLimit(family == .systemLarge ? 2 : 1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Widget "Gedanke notieren" (Schnellzugriff auf dem Sperrbildschirm)

struct ThoughtCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ThoughtCaptureWidget", provider: CaptureProvider()) { _ in
            CaptureView()
                .containerBackground(for: .widget) { Theme.background }
                .widgetURL(URL(string: "tagesplaner://thoughts/new"))
        }
        .configurationDisplayName("Gedanke notieren")
        .description("Ein Tippen öffnet direkt das Eingabefeld.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .systemSmall])
    }
}

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: Date())], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct CaptureView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Gedanke notieren", systemImage: "plus.bubble")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus.bubble")
                    .font(.system(size: 20, weight: .semibold))
            }
            .widgetAccentable()
        default:
            VStack(spacing: 8) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                Text("Gedanke\nnotieren")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
