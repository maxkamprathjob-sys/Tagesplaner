import Foundation
import NaturalLanguage

/// Semantische Wortähnlichkeit mit Apples eingebautem deutschen Wortmodell
/// (NaturalLanguage, läuft vollständig auf dem iPhone). Fehlt das Modell, liefert sie 0.
enum SemanticSimilarity {
    private static let embedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .german)

    static var isAvailable: Bool { embedding != nil }

    /// Größte Ähnlichkeit (0…1) zwischen einem Wort und einer Liste von Begriffen.
    static func best(_ token: String, _ terms: [String]) -> Double {
        guard let e = embedding, e.contains(token) else { return 0 }
        var best = 0.0
        for term in terms where term != token && e.contains(term) {
            let distance = e.distance(between: token, and: term, distanceType: .cosine)
            best = max(best, 1 - distance)
        }
        return best
    }
}
