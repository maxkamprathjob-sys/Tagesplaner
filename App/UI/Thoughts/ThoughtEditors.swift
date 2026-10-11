import SwiftUI
import PlannerCore

/// Gedanken bearbeiten, verschieben oder löschen.
struct ThoughtEditorView: View {
    let thought: Thought
    @EnvironmentObject private var thoughts: ThoughtStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var target: FolderTarget = .unsorted
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Gedanke", text: $text, axis: .vertical)
                        .lineLimit(2...10)
                }
                Section("Ordner") {
                    Picker("Ordner", selection: $target) {
                        ForEach(thoughts.folders()) { f in
                            Label(f.name, systemImage: f.symbol).tag(FolderTarget.folder(f.id))
                        }
                        Label(Unsorted.name, systemImage: Unsorted.symbol).tag(FolderTarget.unsorted)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if thought.autoSorted && !thought.matchedText.isEmpty {
                    Section {
                        Text("Automatisch erkannt an: \(thought.matchedText)")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Gedanke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let original = FolderTarget(thought.folderID)
                        if target != original {
                            thoughts.move(thought, to: target)
                        }
                        thoughts.updateText(thought, to: text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Gedanken löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    thoughts.delete(thought)
                    dismiss()
                }
            }
            .onAppear {
                text = thought.text
                target = FolderTarget(thought.folderID)
            }
        }
    }
}

/// Schnelles Verschieben in einen anderen Ordner.
struct MoveThoughtSheet: View {
    let thought: Thought
    @EnvironmentObject private var thoughts: ThoughtStore
    @EnvironmentObject private var ui: UIState
    @Environment(\.dismiss) private var dismiss
    @State private var newFolder = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(thought.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(thoughts.folders()) { f in
                        option(f.name, f.symbol, target: .folder(f.id))
                    }
                    option(Unsorted.name, Unsorted.symbol, target: .unsorted)
                    Button {
                        newFolder = true
                    } label: {
                        Label("Neuer Ordner …", systemImage: "folder.badge.plus")
                            .foregroundStyle(Theme.accentText)
                    }
                    .listRowBackground(Theme.surface)
                } footer: {
                    Text("Die Sortierung merkt sich deine Korrekturen und ordnet ähnliche Gedanken künftig genauso ein.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Verschieben nach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .sheet(isPresented: $newFolder) {
                NavigationStack {
                    FolderEditorView(folder: nil) { created in
                        thoughts.move(thought, to: .folder(created.id))
                        dismiss()
                    }
                }
            }
        }
    }

    private func option(_ name: String, _ symbol: String, target: FolderTarget) -> some View {
        let current = FolderTarget(thought.folderID) == target
        return Button {
            thoughts.move(thought, to: target)
            ui.showToast("Nach „\(name)“ verschoben")
            dismiss()
        } label: {
            HStack {
                Label(name, systemImage: symbol)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if current { Image(systemName: "checkmark").foregroundStyle(Theme.accentText) }
            }
        }
        .listRowBackground(Theme.surface)
    }
}

/// Ordner anlegen, umbenennen, sortieren, löschen.
struct FolderManagerView: View {
    @EnvironmentObject private var thoughts: ThoughtStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = thoughts.revision
        let all = thoughts.allThoughts()
        NavigationStack {
            List {
                Section {
                    ForEach(thoughts.folders()) { f in
                        NavigationLink {
                            FolderEditorView(folder: f)
                        } label: {
                            HStack {
                                Label(f.name, systemImage: f.symbol)
                                Spacer()
                                Text("\(all.filter { $0.folderID == f.id }.count)")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .onMove { thoughts.reorderFolders(from: $0, to: $1) }
                } footer: {
                    Text("Reihenfolge ändern: „Bearbeiten“ tippen und ziehen.")
                }
                Section {
                    NavigationLink {
                        FolderEditorView(folder: nil)
                    } label: {
                        Label("Neuer Ordner", systemImage: "folder.badge.plus")
                            .foregroundStyle(Theme.accentText)
                    }
                }
                Section {
                    Button {
                        let n = thoughts.sortUnsorted()
                        sortedInfo = n == 0 ? "Keine unsortierten Gedanken konnten sicher zugeordnet werden."
                                            : "\(n) Gedanken einsortiert."
                    } label: {
                        Label("Unsortierte jetzt einordnen", systemImage: "wand.and.stars")
                    }
                    if let sortedInfo {
                        Text(sortedInfo).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                } footer: {
                    Text("Die Sortierung läuft komplett auf deinem iPhone: eingebautes Wissen über typische Begriffe, Apples Sprachmodell für ähnliche Wörter und alles, was sie aus deinem Verschieben lernt. Mit „#ordnername“ im Text bestimmst du den Ordner selbst.")
                }
            }
            .navigationTitle("Ordner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    @State private var sortedInfo: String?
}

/// Ordner anlegen oder bearbeiten.
struct FolderEditorView: View {
    let folder: ThoughtFolder?
    var onCreated: ((ThoughtFolder) -> Void)? = nil
    @EnvironmentObject private var thoughts: ThoughtStore
    @EnvironmentObject private var ui: UIState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "folder"
    @State private var keywords = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    static let symbols = [
        "folder", "briefcase", "sparkles", "person.2", "checklist", "house", "graduationcap", "book",
        "figure.run", "heart", "cart", "fork.knife", "airplane", "car", "gift", "lightbulb",
        "music.note", "film", "gamecontroller", "leaf", "pawprint", "eurosign.circle", "cross.case", "hammer",
        "paintbrush", "camera", "star", "flag", "bell", "brain.head.profile"
    ]

    var body: some View {
        let known = ThoughtClassifier.knownTerms(forFolderNamed: name)
        Form {
            Section("Name") {
                TextField("z. B. Uni, Sport, Ideen", text: $name)
                    .font(.headline)
            }
            Section("Symbol") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                    ForEach(Self.symbols, id: \.self) { s in
                        Button {
                            symbol = s
                        } label: {
                            Image(systemName: s)
                                .font(.system(size: 18))
                                .frame(width: 42, height: 42)
                                .background(symbol == s ? Theme.accent : Theme.surfaceStrong,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(symbol == s ? Color.white : Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                TextField("z. B. Training, Verein, Turnier", text: $keywords, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Stichwörter (optional)")
            } footer: {
                if !known.isEmpty {
                    Text("Die Sortierung kennt für diesen Ordner bereits u. a.: \(known.prefix(12).joined(separator: ", ")) …")
                } else {
                    Text("Ein paar typische Wörter helfen der Sortierung. Sie lernt außerdem aus jedem Gedanken, den du hierher verschiebst.")
                }
            }
            if let folder {
                Section {
                    LabeledContent("Gelernte Begriffe", value: "\(folder.learned.filter { $0.value > 0 }.count)")
                    Button("Gelerntes zurücksetzen") { thoughts.resetLearning(folder) }
                        .disabled(folder.learned.isEmpty)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Ordner löschen", systemImage: "trash")
                    }
                } footer: {
                    Text("Beim Löschen bleiben die Gedanken erhalten und landen in „Unsortiert“.")
                }
            }
        }
        .navigationTitle(folder == nil ? "Neuer Ordner" : "Ordner bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if folder == nil { Button("Abbrechen") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save)
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Ordner „\(name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let folder { thoughts.deleteFolder(folder) }
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let folder {
                name = folder.name
                symbol = folder.symbol
                keywords = folder.keywordsText
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let folder {
            thoughts.updateFolder(folder, name: trimmed, symbol: symbol, keywords: keywords)
        } else {
            let result = thoughts.addFolder(name: trimmed, symbol: symbol, keywords: keywords)
            if result.moved > 0 {
                ui.showToast(result.moved == 1 ? "1 Gedanke nach „\(trimmed)“ einsortiert"
                                               : "\(result.moved) Gedanken nach „\(trimmed)“ einsortiert")
            }
            onCreated?(result.folder)
        }
        dismiss()
    }
}
