import XCTest
import SwiftData
import PlannerCore
@testable import Tagesplaner

@MainActor
final class ThoughtStoreTests: XCTestCase {
    private var containers: [ModelContainer] = []

    override func tearDown() {
        containers.removeAll()
        super.tearDown()
    }

    private func makeStore(url: URL? = nil) -> ThoughtStore {
        let c = url.map { Persistence.makeContainer(url: $0) } ?? Persistence.makeContainer(inMemory: true)
        containers.append(c)
        let store = ThoughtStore(context: c.mainContext, defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!)
        store.integrationsEnabled = false
        store.semanticEnabled = false
        store.ensureDefaultFolders()
        return store
    }

    private func folderName(_ store: ThoughtStore, _ t: Thought) -> String {
        store.name(of: FolderTarget(t.folderID))
    }

    func testDefaultFoldersSeededOnce() {
        let store = makeStore()
        XCTAssertEqual(store.folders().map(\.name), ["Arbeit", "Freizeit", "Freunde", "Aufgaben", "Haushalt"])
        store.ensureDefaultFolders()
        XCTAssertEqual(store.folders().count, 5)
    }

    func testAddSortsAutomatically() {
        let store = makeStore()
        let r = store.add("Wäsche waschen nicht vergessen")
        XCTAssertEqual(store.name(of: r!.target), "Haushalt")
        XCTAssertTrue(r!.wasAutomatic)
        XCTAssertTrue(r!.matched.contains("waschen"))

        let unclear = store.add("blubb")
        XCTAssertEqual(unclear?.target, .unsorted)
        XCTAssertNil(store.add("   "))
    }

    func testExplicitTargetAndTag() {
        let store = makeStore()
        let freunde = store.folders().first { $0.name == "Freunde" }!
        let r = store.add("Netflix Abend", to: .folder(freunde.id))
        XCTAssertEqual(r?.target, .folder(freunde.id))

        let tagged = store.add("#arbeit Laptop zurückgeben")
        XCTAssertEqual(store.name(of: tagged!.target), "Arbeit")
        XCTAssertEqual(store.thought(id: tagged!.thoughtID)?.text, "Laptop zurückgeben")
    }

    func testMoveLearnsForNextTime() {
        let store = makeStore()
        let r = store.add("Bauantrag Müller durchsehen")!
        XCTAssertNotEqual(store.name(of: r.target), "Arbeit")
        let arbeit = store.folders().first { $0.name == "Arbeit" }!
        store.move(store.thought(id: r.thoughtID)!, to: .folder(arbeit.id))

        let next = store.add("Bauantrag Schulze durchsehen")!
        XCTAssertEqual(store.name(of: next.target), "Arbeit")
    }

    func testCustomFolderPicksUpUnsorted() {
        let store = makeStore()
        let r = store.add("Gartenschlauch reparieren lassen")!
        // Ohne Garten-Ordner landet es woanders oder unsortiert.
        XCTAssertNotEqual(store.name(of: r.target), "Garten")
        if r.target != .unsorted {
            store.move(store.thought(id: r.thoughtID)!, to: .unsorted)
        }
        let result = store.addFolder(name: "Garten", symbol: "leaf", keywords: "")
        XCTAssertEqual(result.moved, 1)
        XCTAssertEqual(store.thoughts(in: .folder(result.folder.id)).count, 1)

        let next = store.add("Gartenmöbel streichen")!
        XCTAssertEqual(next.target, .folder(result.folder.id))
    }

    func testDeleteFolderKeepsThoughts() {
        let store = makeStore()
        store.add("Milch kaufen")
        let haushalt = store.folders().first { $0.name == "Haushalt" }!
        XCTAssertEqual(store.thoughts(in: .folder(haushalt.id)).count, 1)
        store.deleteFolder(haushalt)
        XCTAssertEqual(store.allThoughts().count, 1)
        XCTAssertEqual(store.thoughts(in: .unsorted).count, 1)
        XCTAssertEqual(store.folders().count, 4)
    }

    func testDeleteAndUndo() {
        let store = makeStore()
        let r = store.add("Anna anrufen wegen Party")!
        let backup = store.delete(store.thought(id: r.thoughtID)!)
        XCTAssertTrue(store.allThoughts().isEmpty)
        store.restore(backup)
        XCTAssertEqual(store.allThoughts().first?.text, "Anna anrufen wegen Party")
        XCTAssertEqual(folderName(store, store.allThoughts().first!), "Freunde")
    }

    func testReorderFolders() {
        let store = makeStore()
        store.reorderFolders(from: IndexSet(integer: 4), to: 0)
        XCTAssertEqual(store.folders().first?.name, "Haushalt")
    }

    func testSnapshotForWidgets() {
        let store = makeStore()
        store.add("Milch kaufen")
        store.add("blubb")
        let snap = store.makeSnapshot()
        XCTAssertEqual(snap.items.count, 2)
        XCTAssertEqual(snap.folders.first { $0.name == "Haushalt" }?.count, 1)
        XCTAssertEqual(snap.folders.first { $0.id == ThoughtsSnapshot.unsortedID }?.count, 1)
        let haushaltID = snap.folders.first { $0.name == "Haushalt" }!.id
        XCTAssertEqual(snap.items(inFolder: haushaltID).map(\.text), ["Milch kaufen"])
    }

    func testThoughtsPersist() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("thoughts-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = makeStore(url: url)
            store.add("Steuererklärung abgeben")
            store.addFolder(name: "Uni", symbol: "graduationcap", keywords: "Bauko")
        }
        containers.removeAll()
        let reopened = Persistence.makeContainer(url: url)
        containers.append(reopened)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Thought>()).count, 1)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<ThoughtFolder>()).count, 6)
    }
}
