import SwiftUI
import PlannerCore

/// Reiter "Gedanken": schnell festhalten, automatisch einsortieren,
/// verschieben, löschen, eigene Ordner.
struct ThoughtsView: View {
    @EnvironmentObject private var thoughts: ThoughtStore
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState

    enum Filter: Hashable {
        case all
        case target(FolderTarget)
    }

    @State private var filter: Filter = .all
    @State private var editing: Thought?
    @State private var moving: Thought?
    @State private var showFolders = false
    @State private var newFolder = false
    @State private var lastAdded: ThoughtStore.AddResult?
    @State private var lastDeleted: ThoughtStore.Deleted?

    var body: some View {
        let _ = thoughts.revision
        let folders = thoughts.folders()
        let all = thoughts.allThoughts()

        NavigationStack {
            VStack(spacing: 0) {
                header(count: all.count)
                FolderChips(filter: $filter, folders: folders, thoughts: all, onAdd: { newFolder = true })
                    .padding(.bottom, 6)
                list(folders: folders, all: all)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    banners
                    ThoughtInputBar(preferred: preferredTarget) { result in
                        withAnimation { lastAdded = result; lastDeleted = nil }
                        hideLater(result.id)
                    }
                }
                .padding(.bottom, 4)
                .background(Theme.background.opacity(0.95))
            }
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
        .sheet(item: $editing) { t in
            ThoughtEditorView(thought: t)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.background)
        }
        .sheet(item: $moving) { t in
            MoveThoughtSheet(thought: t)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showFolders) { FolderManagerView() }
        .sheet(isPresented: $newFolder) {
            NavigationStack { FolderEditorView(folder: nil) }
        }
    }

    /// Ist ein Ordner ausgewählt, landen neue Gedanken trotzdem automatisch –
    /// außer der Benutzer wählt im Eingabefeld etwas anderes.
    private var preferredTarget: FolderTarget? { nil }

    // MARK: Kopf

    private func header(count: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GEDANKEN")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accentText)
                Text(count == 1 ? "1 Gedanke · automatisch sortiert" : "\(count) Gedanken · automatisch sortiert")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                showFolders = true
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
                    .foregroundStyle(Theme.textPrimary)
            }
            .accessibilityLabel("Ordner verwalten")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Liste

    @ViewBuilder
    private func list(folders: [ThoughtFolder], all: [Thought]) -> some View {
        if all.isEmpty {
            emptyState
        } else {
            List {
                switch filter {
                case .all:
                    let unsorted = all.filter { $0.folderID == nil }
                    if !unsorted.isEmpty {
                        section(title: Unsorted.name, symbol: Unsorted.symbol, items: unsorted, showFolder: false,
                                footer: "Nicht eindeutig erkannt – wische nach rechts zum Einordnen.")
                    }
                    ForEach(folders) { f in
                        let items = all.filter { $0.folderID == f.id }
                        if !items.isEmpty {
                            section(title: f.name, symbol: f.symbol, items: items, showFolder: false, footer: nil)
                        }
                    }
                case .target(let target):
                    let items = all.filter { $0.folderID == target.folderID }
                    if items.isEmpty {
                        Text("Dieser Ordner ist leer.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.surface)
                    } else {
                        Section {
                            ForEach(items) { row($0, showFolder: false) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func section(title: String, symbol: String, items: [Thought], showFolder: Bool, footer: String?) -> some View {
        Section {
            ForEach(items) { row($0, showFolder: showFolder) }
        } header: {
            Label("\(title) · \(items.count)", systemImage: symbol)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
        } footer: {
            if let footer {
                Text(footer).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func row(_ t: Thought, showFolder: Bool) -> some View {
        ThoughtRow(thought: t, folderName: thoughts.name(of: FolderTarget(t.folderID)),
                   symbol: thoughts.symbol(of: FolderTarget(t.folderID)), showFolder: showFolder)
            .contentShape(Rectangle())
            .onTapGesture { editing = t }
            .listRowBackground(Theme.surface)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { delete(t) } label: { Label("Löschen", systemImage: "trash") }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { moving = t } label: { Label("Verschieben", systemImage: "folder") }
                    .tint(Theme.accent)
            }
            .contextMenu {
                Menu {
                    ForEach(thoughts.folders()) { f in
                        Button { thoughts.move(t, to: .folder(f.id)) } label: { Label(f.name, systemImage: f.symbol) }
                    }
                    Button { thoughts.move(t, to: .unsorted) } label: { Label(Unsorted.name, systemImage: Unsorted.symbol) }
                } label: {
                    Label("Verschieben nach", systemImage: "folder")
                }
                Button { editing = t } label: { Label("Bearbeiten", systemImage: "pencil") }
                Button { convertToTask(t) } label: { Label("Als Aufgabe übernehmen", systemImage: "checklist") }
                Button(role: .destructive) { delete(t) } label: { Label("Löschen", systemImage: "trash") }
            }
            .draggable(t.id.uuidString)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accentText)
            Text("Halte fest, was dir durch den Kopf geht.")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Einfach eintippen – die App sortiert es in den passenden Ordner. Mit „#ordner“ wählst du selbst.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Hinweise

    @ViewBuilder
    private var banners: some View {
        if let added = lastAdded {
            HStack(spacing: 10) {
                Image(systemName: thoughts.symbol(of: added.target))
                    .foregroundStyle(Theme.accentText)
                VStack(alignment: .leading, spacing: 1) {
                    Text("In „\(thoughts.name(of: added.target))“ \(added.target == .unsorted ? "abgelegt" : "einsortiert")")
                        .font(.subheadline.weight(.semibold))
                    if added.wasAutomatic && !added.matched.isEmpty {
                        Text("erkannt an: \(added.matched.prefix(3).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Button("Ändern") {
                    if let t = thoughts.thought(id: added.thoughtID) { moving = t }
                    lastAdded = nil
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
            }
            .padding(12)
            .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let deleted = lastDeleted {
            HStack {
                Text("Gedanke gelöscht").font(.subheadline.weight(.medium))
                Spacer()
                Button("Rückgängig") {
                    thoughts.restore(deleted)
                    lastDeleted = nil
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
            }
            .padding(12)
            .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Aktionen

    private func delete(_ t: Thought) {
        let backup = thoughts.delete(t)
        withAnimation { lastDeleted = backup; lastAdded = nil }
        let marker = backup.createdAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if lastDeleted?.createdAt == marker { withAnimation { lastDeleted = nil } }
        }
    }

    private func hideLater(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if lastAdded?.id == id { withAnimation { lastAdded = nil } }
        }
    }

    /// Übernimmt den Gedanken als Aufgabe in den Planer (Datum/Uhrzeit/Dauer werden erkannt).
    private func convertToTask(_ t: Thought) {
        let parsed = NaturalLanguageParser(calendar: store.calendar).parse(t.text, now: store.now)
        let result = store.create(from: parsed, selectedDay: Date(), asTask: true)
        delete(t)
        let day = Fmt.relativeDayName(result.item.day) ?? Fmt.shortDay(result.item.day)
        ui.showToast("Aufgabe angelegt: \(day)")
    }
}

// MARK: - Bausteine

struct ThoughtRow: View {
    let thought: Thought
    let folderName: String
    let symbol: String
    let showFolder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(thought.text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if showFolder {
                    Label(folderName, systemImage: symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accentText)
                }
                Text(thought.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Ordner-Leiste oben. Gedanken lassen sich per Drag & Drop auf einen Ordner ziehen.
struct FolderChips: View {
    @Binding var filter: ThoughtsView.Filter
    let folders: [ThoughtFolder]
    let thoughts: [Thought]
    let onAdd: () -> Void
    @EnvironmentObject private var store: ThoughtStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Alle", "square.grid.2x2", count: thoughts.count, value: .all, drop: nil)
                ForEach(folders) { f in
                    chip(f.name, f.symbol, count: thoughts.filter { $0.folderID == f.id }.count,
                         value: .target(.folder(f.id)), drop: .folder(f.id))
                }
                let unsorted = thoughts.filter { $0.folderID == nil }.count
                if unsorted > 0 {
                    chip(Unsorted.name, Unsorted.symbol, count: unsorted, value: .target(.unsorted), drop: .unsorted)
                }
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 34)
                        .background(Theme.surface, in: Capsule())
                        .foregroundStyle(Theme.accentText)
                }
                .accessibilityLabel("Neuer Ordner")
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, _ symbol: String, count: Int, value: ThoughtsView.Filter, drop: FolderTarget?) -> some View {
        let selected = filter == value
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { filter = value }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.subheadline.weight(.medium))
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(selected ? Theme.accent : Theme.surface, in: Capsule())
            .foregroundStyle(selected ? Color.white : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard let drop, let raw = items.first, let id = UUID(uuidString: raw),
                  let t = store.thought(id: id) else { return false }
            store.move(t, to: drop)
            return true
        }
    }
}

/// Eingabe unten. Zeigt live, in welchen Ordner der Gedanke einsortiert würde.
struct ThoughtInputBar: View {
    let preferred: FolderTarget?
    let onAdded: (ThoughtStore.AddResult) -> Void
    @EnvironmentObject private var thoughts: ThoughtStore
    @EnvironmentObject private var ui: UIState
    @State private var text = ""
    @State private var override: FolderTarget?
    @FocusState private var focused: Bool

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prediction = trimmed.isEmpty ? nil : thoughts.classify(trimmed)
        let target = override ?? preferred ?? prediction?.target

        VStack(alignment: .leading, spacing: 6) {
            if let target, !trimmed.isEmpty {
                Menu {
                    Button { override = nil } label: { Label("Automatisch", systemImage: "wand.and.stars") }
                    Divider()
                    ForEach(thoughts.folders()) { f in
                        Button { override = .folder(f.id) } label: { Label(f.name, systemImage: f.symbol) }
                    }
                    Button { override = .unsorted } label: { Label(Unsorted.name, systemImage: Unsorted.symbol) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: override == nil ? "wand.and.stars" : "hand.point.up.left")
                        Text("→ \(thoughts.name(of: target))")
                            .fontWeight(.semibold)
                        if override == nil, let m = prediction?.matched.first {
                            Text("(\(m))").foregroundStyle(Theme.textSecondary)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accentFill, in: Capsule())
                    .foregroundStyle(Theme.accentText)
                }
                .padding(.horizontal, 16)
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Gedanke festhalten …", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(save)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.accent.opacity(focused ? 0.8 : 0.4), lineWidth: 1))
                Button(action: save) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(trimmed.isEmpty ? Theme.surface : Theme.accent, in: Circle())
                        .foregroundStyle(trimmed.isEmpty ? Theme.textSecondary : Color.white)
                }
                .disabled(trimmed.isEmpty)
                .accessibilityLabel("Speichern")
            }
            .padding(.horizontal, 16)
        }
        .animation(.easeInOut(duration: 0.15), value: trimmed.isEmpty)
        .onAppear { if ui.focusThoughtInput { focused = true; ui.focusThoughtInput = false } }
        .onChange(of: ui.focusThoughtInput) { _, want in
            if want { focused = true; ui.focusThoughtInput = false }
        }
    }

    private func save() {
        guard let result = thoughts.add(text, to: override ?? preferred) else { return }
        text = ""
        override = nil
        onAdded(result)
    }
}
