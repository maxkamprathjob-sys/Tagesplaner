import XCTest
@testable import PlannerCore

final class ThoughtClassifierTests: XCTestCase {

    private let defaults = [
        ThoughtFolderProfile(id: "arbeit", name: "Arbeit"),
        ThoughtFolderProfile(id: "freizeit", name: "Freizeit"),
        ThoughtFolderProfile(id: "freunde", name: "Freunde"),
        ThoughtFolderProfile(id: "aufgaben", name: "Aufgaben"),
        ThoughtFolderProfile(id: "haushalt", name: "Haushalt")
    ]

    private func folder(_ text: String, _ folders: [ThoughtFolderProfile]? = nil) -> String? {
        ThoughtClassifier().classify(text, folders: folders ?? defaults).folderID
    }

    func testDefaultFolders() {
        XCTAssertEqual(folder("Wäsche waschen nicht vergessen"), "haushalt")
        XCTAssertEqual(folder("Milch und Eier kaufen"), "haushalt")
        XCTAssertEqual(folder("Chef wegen Urlaubstagen fragen"), "arbeit")
        XCTAssertEqual(folder("Präsentation für das Meeting vorbereiten"), "arbeit")
        XCTAssertEqual(folder("Lisa zum Geburtstag gratulieren"), "freunde")
        XCTAssertEqual(folder("Anna anrufen wegen Party"), "freunde")
        XCTAssertEqual(folder("Neue Serie auf Netflix anschauen"), "freizeit")
        XCTAssertEqual(folder("Steuererklärung abgeben"), "aufgaben")
        XCTAssertEqual(folder("Hausarbeit fertigstellen"), "aufgaben")
    }

    func testUnclearGoesToUnsorted() {
        XCTAssertNil(folder("xyz blubb"))
        XCTAssertNil(folder("Ich muss"))
        XCTAssertNil(folder(""))
    }

    func testMatchedTermsAreReported() {
        let result = ThoughtClassifier().classify("Bad putzen", folders: defaults)
        XCTAssertEqual(result.folderID, "haushalt")
        XCTAssertTrue(result.matchedTerms.contains("putzen"))
    }

    func testExplicitTag() {
        XCTAssertEqual(folder("#arbeit Laptop zurückgeben"), "arbeit")
        XCTAssertEqual(folder("Laptop zurückgeben #frei"), "freizeit")
        XCTAssertEqual(ThoughtClassifier.removingTags(from: "#arbeit Laptop zurückgeben"), "Laptop zurückgeben")
    }

    func testCustomFolderWithBuiltInKnowledge() {
        let folders = defaults + [ThoughtFolderProfile(id: "uni", name: "Uni", isCustom: true)]
        XCTAssertEqual(folder("Klausur Baukonstruktion anmelden", folders), "uni")
        XCTAssertEqual(folder("Vorlesung nacharbeiten", folders), "uni")
        // Ohne Uni-Ordner landet es bei den Aufgaben
        XCTAssertEqual(folder("Klausur Baukonstruktion anmelden"), "aufgaben")
    }

    func testCustomFolderByNameAndKeywords() {
        let garten = ThoughtFolderProfile(id: "garten", name: "Garten", isCustom: true)
        XCTAssertEqual(folder("Gartenschlauch kaufen", defaults + [garten]), "garten")

        let verein = ThoughtFolderProfile(id: "verein", name: "Handball", keywords: ["Trikot", "Auswärtsspiel"], isCustom: true)
        XCTAssertEqual(folder("Trikots waschen fürs Auswärtsspiel", defaults + [verein]), "verein")
    }

    func testLearningFromCorrections() {
        XCTAssertNotEqual(folder("Bauantrag durchsehen"), "arbeit")
        var arbeit = defaults[0]
        for key in ThoughtClassifier.learningKeys(for: "Bauantrag Müller prüfen") {
            arbeit.learned[key, default: 0] += 1.2
        }
        let folders = [arbeit] + defaults.dropFirst()
        XCTAssertEqual(folder("Bauantrag durchsehen", folders), "arbeit")
    }

    func testNegativeLearningMovesAway() {
        var freizeit = defaults[1]
        freizeit.learned[ThoughtClassifier.stem(ThoughtClassifier.normalize("serie"))] = -2
        let result = ThoughtClassifier().classify("Serie", folders: [defaults[0], freizeit])
        XCTAssertNil(result.folderID)
    }

    func testSemanticRescue() {
        var classifier = ThoughtClassifier { token, terms in
            (token == "hantelbank" && terms.contains("sport")) ? 0.8 : 0
        }
        classifier.threshold = 1.0
        let sport = ThoughtFolderProfile(id: "sport", name: "Sport", isCustom: true)
        XCTAssertEqual(classifier.classify("Hantelbank anschauen", folders: [sport]).folderID, "sport")
    }

    func testKnownTerms() {
        XCTAssertTrue(ThoughtClassifier.knownTerms(forFolderNamed: "Uni").contains("klausur"))
        XCTAssertTrue(ThoughtClassifier.knownTerms(forFolderNamed: "Mein Garten").isEmpty)
    }
}
