import SwiftUI
import PlannerCore

/// "Tag planen": Vorschläge für alle offenen Aufgaben – nach Dringlichkeit und Priorität.
/// Der Benutzer wählt aus, was übernommen wird.
struct PlanDayView: View {
    let day: Date
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState
    @Environment(\.dismiss) private var dismiss

    @State private var proposals: [Proposal] = []
    @State private var selected: Set<UUID> = []

    struct Proposal: Identifiable {
        var id: UUID { itemID }
        var itemID: UUID
        var title: String
        var priority: Priority
        var interval: DateInterval?
        var problem: String?
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wichtige und dringende Aufgaben werden zuerst verteilt. Übernommen wird nur, was du auswählst.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(proposals) { p in
                        row(p)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Tag planen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen (\(selected.count))") { apply() }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty)
                }
            }
            .onAppear(perform: compute)
        }
    }

    @ViewBuilder
    private func row(_ p: Proposal) -> some View {
        let isOn = selected.contains(p.itemID)
        HStack(spacing: 12) {
            if p.interval != nil {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? Theme.accentText : Theme.textSecondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warning)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.title)
                    if p.priority >= .high {
                        Text(p.priority == .veryHigh ? "!!!" : "!!")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.accentText)
                    }
                }
                if let iv = p.interval {
                    Text(Fmt.range(iv.start, iv.end))
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                } else if let problem = p.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard p.interval != nil else { return }
            if isOn { selected.remove(p.itemID) } else { selected.insert(p.itemID) }
        }
        .listRowBackground(Theme.surface)
    }

    private func compute() {
        proposals = store.planDayProposals(on: day).map { entry in
            let item = entry.item
            switch entry.result {
            case .suggestion(let s):
                return Proposal(itemID: item.id, title: item.title, priority: item.priority, interval: s.interval, problem: s.deadlineWarning)
            case .noFit(let n):
                return Proposal(itemID: item.id, title: item.title, priority: item.priority, interval: nil,
                                problem: "Passt nicht mehr – es fehlen ungefähr \(DurationText.approximate(n.missingMinutes))")
            }
        }
        selected = Set(proposals.filter { $0.interval != nil }.map(\.itemID))
    }

    private func apply() {
        var count = 0
        for p in proposals where selected.contains(p.itemID) {
            if let iv = p.interval, let item = store.item(id: p.itemID) {
                item.setSchedule(iv, calendar: store.calendar)
                count += 1
            }
        }
        store.commitEdit()
        ui.showToast(count == 1 ? "1 Aufgabe eingeplant" : "\(count) Aufgaben eingeplant")
        ui.tab = .plan
        dismiss()
    }
}
