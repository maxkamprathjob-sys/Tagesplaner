import Foundation

/// Ein Ordner aus Sicht der Sortier-Logik.
public struct ThoughtFolderProfile: Hashable, Sendable {
    public var id: String
    public var name: String
    /// Vom Benutzer eingetragene Stichwörter.
    public var keywords: [String]
    /// Aus Korrekturen gelernte Gewichte (Schlüssel = Wortstamm).
    public var learned: [String: Double]
    /// Eigene Ordner sind spezifischer und gewinnen bei Gleichstand.
    public var isCustom: Bool

    public init(id: String, name: String, keywords: [String] = [], learned: [String: Double] = [:], isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.learned = learned
        self.isCustom = isCustom
    }
}

public struct ThoughtClassification: Equatable, Sendable {
    /// nil = keine ausreichend sichere Zuordnung → "Unsortiert".
    public var folderID: String?
    public var score: Double
    /// Wörter, an denen der Ordner erkannt wurde (für die Anzeige).
    public var matchedTerms: [String]
    public var scores: [String: Double]
}

/// Lokale, lernende Sortierung von Gedanken in Ordner.
///
/// Signale (alle auf dem Gerät, ohne Cloud):
/// 1. eingebautes Wissen über typische Begriffe pro Thema (auch für eigene Ordner wie "Uni", "Sport", "Finanzen" …),
/// 2. Ordnername und eigene Stichwörter,
/// 3. Gelerntes aus deinem Verschieben,
/// 4. optional semantische Wortähnlichkeit (in der App: Apples NaturalLanguage-Wortmodell).
/// Explizit: "#ordner" im Text wählt den Ordner direkt.
public struct ThoughtClassifier {
    public typealias SemanticScorer = (_ token: String, _ terms: [String]) -> Double

    public var semantic: SemanticScorer?
    public var threshold: Double = 1.0
    public var customBoost: Double = 1.3

    public init(semantic: SemanticScorer? = nil) {
        self.semantic = semantic
    }

    // MARK: Klassifizieren

    public func classify(_ text: String, folders: [ThoughtFolderProfile]) -> ThoughtClassification {
        if let tagged = Self.taggedFolder(in: text, folders: folders) {
            return ThoughtClassification(folderID: tagged.id, score: 99, matchedTerms: ["#" + tagged.name], scores: [tagged.id: 99])
        }
        let tokens = Self.tokenize(text)
        let normText = " " + Self.tokenize(text, dropStopwords: false).map(\.norm).joined(separator: " ") + " "
        var scores: [String: Double] = [:]
        var best: (id: String, score: Double, matched: [String])?

        for folder in folders {
            let terms = Self.terms(for: folder)
            var score = 0.0
            var matched: [String] = []

            // 1 + 2: Begriffe
            for token in tokens {
                var tokenBest = 0.0
                for term in terms where !term.isPhrase {
                    let f = Self.matchFactor(token: token, term: term)
                    if f > 0 { tokenBest = max(tokenBest, f * term.weight) }
                }
                if tokenBest > 0 {
                    score += tokenBest
                    if tokenBest >= 1.0 { matched.append(token.raw) }
                }
            }
            for term in terms where term.isPhrase && normText.contains(" " + term.norm + " ") {
                score += term.weight
                matched.append(term.raw)
            }

            // 3: Gelerntes
            for token in tokens {
                if let w = folder.learned[token.stem] {
                    score += max(-2, min(2, w))
                    if w >= 1 { matched.append(token.raw) }
                }
            }

            // 4: Semantik – nur als Rettung, wenn die Begriffe nicht reichen
            if let semantic, score < threshold, !tokens.isEmpty {
                let semanticTerms = Self.semanticTerms(for: folder)
                var bestSim = 0.0
                var bestToken = ""
                for token in tokens where token.raw.count >= 3 {
                    let sim = semantic(token.raw, semanticTerms)
                    if sim > bestSim { bestSim = sim; bestToken = token.raw }
                }
                if bestSim >= 0.6 {
                    score += min(1.5, (bestSim - 0.5) * 3)
                    matched.append(bestToken)
                }
            }

            if folder.isCustom { score *= customBoost }
            scores[folder.id] = score
            if best == nil || score > best!.score {
                best = (folder.id, score, matched)
            }
        }

        guard let b = best, b.score >= threshold else {
            return ThoughtClassification(folderID: nil, score: best?.score ?? 0, matchedTerms: [], scores: scores)
        }
        var seen = Set<String>()
        let unique = b.matched.filter { seen.insert($0).inserted }
        return ThoughtClassification(folderID: b.id, score: b.score, matchedTerms: unique, scores: scores)
    }

    /// Wortstämme, die beim Verschieben eines Gedankens gelernt werden.
    public static func learningKeys(for text: String) -> [String] {
        var seen = Set<String>()
        return tokenize(text).map(\.stem).filter { $0.count >= 3 && seen.insert($0).inserted }
    }

    /// Begriffe, die die Sortierung für einen Ordnernamen bereits kennt (zur Anzeige).
    public static func knownTerms(forFolderNamed name: String) -> [String] {
        var seen = Set<String>()
        return packs(forFolderNamed: name).flatMap { $0.strong }.filter { seen.insert($0).inserted }
    }

    // MARK: Text

    public struct Token: Hashable {
        public var raw: String
        public var norm: String
        public var stem: String
    }

    public static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ẞ", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
    }

    public static func tokenize(_ text: String, dropStopwords: Bool = true) -> [Token] {
        let lower = text.lowercased()
        let parts = lower.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        return parts.compactMap { raw in
            let norm = normalize(raw)
            guard norm.count >= 2 else { return nil }
            if dropStopwords && stopwords.contains(norm) { return nil }
            return Token(raw: raw, norm: norm, stem: stem(norm))
        }
    }

    /// Sehr einfacher deutscher Wortstamm (für Plural/Beugung).
    public static func stem(_ word: String) -> String {
        var s = word
        for suffix in ["ungen", "ung", "en", "er", "es", "em", "e", "n", "s"] {
            if s.hasSuffix(suffix) && s.count - suffix.count >= 4 {
                s.removeLast(suffix.count)
                break
            }
        }
        return s
    }

    static let stopwords: Set<String> = [
        "ich", "du", "er", "sie", "es", "wir", "ihr", "man", "mich", "mir", "dich", "dir", "uns", "euch",
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines",
        "und", "oder", "aber", "denn", "weil", "dass", "ob", "wenn", "als", "wie", "was", "wer", "wo",
        "mit", "fur", "von", "zu", "zum", "zur", "im", "in", "am", "an", "auf", "aus", "bei", "nach", "vor",
        "uber", "unter", "um", "ab", "bis", "durch", "ohne", "gegen", "wegen", "seit",
        "mein", "meine", "meinen", "meinem", "meiner", "dein", "deine", "sein", "seine", "ihre",
        "noch", "mal", "auch", "dann", "doch", "schon", "nur", "sehr", "so", "ja", "nein", "nicht", "kein", "keine",
        "ist", "sind", "war", "bin", "bist", "habe", "hab", "hat", "haben", "hatte", "will", "mochte", "soll",
        "kann", "konnte", "werde", "wird", "wurde", "gibt", "geht", "heute", "morgen", "gestern", "bitte",
        "wieder", "jetzt", "hier", "da", "dort", "etwas", "was", "alles", "alle", "beispiel", "eigentlich", "einfach"
    ]

    // MARK: Begriffe & Abgleich

    struct Term {
        var raw: String
        var norm: String
        var stem: String
        var weight: Double
        var isPhrase: Bool
    }

    static func makeTerm(_ raw: String, weight: Double) -> Term {
        let norm = normalize(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return Term(raw: raw.lowercased(), norm: norm, stem: stem(norm), weight: weight, isPhrase: norm.contains(" "))
    }

    static func terms(for folder: ThoughtFolderProfile) -> [Term] {
        var result: [Term] = []
        for t in tokenize(folder.name, dropStopwords: true) {
            result.append(makeTerm(t.raw, weight: 2.0))
        }
        for k in folder.keywords where !k.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(makeTerm(k, weight: 1.5))
        }
        for pack in packs(forFolderNamed: folder.name) {
            result += pack.strong.map { makeTerm($0, weight: 1.5) }
            result += pack.weak.map { makeTerm($0, weight: 0.7) }
        }
        return result
    }

    static func semanticTerms(for folder: ThoughtFolderProfile) -> [String] {
        var terms = tokenize(folder.name, dropStopwords: true).map(\.raw)
        terms += folder.keywords.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        for pack in packs(forFolderNamed: folder.name) { terms += pack.strong.prefix(10) }
        return terms.filter { !$0.isEmpty && !$0.contains(" ") }
    }

    /// 1.0 = gleiches Wort/gleicher Stamm, 0.9 = Beugung, 0.75 = Wort beginnt mit dem Begriff
    /// (Kompositum, z. B. "Wäschekorb"), 0.5 = Wort endet mit dem Begriff ("Hausarbeit").
    static func matchFactor(token: Token, term: Term) -> Double {
        if token.norm == term.norm || token.stem == term.stem { return 1.0 }
        if term.stem.count >= 4 && token.norm.hasPrefix(term.stem) && token.norm.count <= term.stem.count + 3 { return 0.9 }
        if term.norm.count >= 4 && token.norm.hasPrefix(term.norm) { return 0.75 }
        if term.norm.count >= 5 && token.norm.hasSuffix(term.norm) { return 0.5 }
        return 0
    }

    static func taggedFolder(in text: String, folders: [ThoughtFolderProfile]) -> ThoughtFolderProfile? {
        guard let regex = try? NSRegularExpression(pattern: "#([\\p{L}\\p{N}_-]+)") else { return nil }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tag = normalize(ns.substring(with: match.range(at: 1)))
            guard tag.count >= 2 else { continue }
            if let f = folders.first(where: { normalize($0.name) == tag }) ?? folders.first(where: { normalize($0.name).hasPrefix(tag) }) {
                return f
            }
        }
        return nil
    }

    /// Entfernt "#ordner"-Markierungen aus dem Text.
    public static func removingTags(from text: String) -> String {
        text.replacingOccurrences(of: "#[\\p{L}\\p{N}_-]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Wissen

    struct Pack {
        var aliases: [String]
        var strong: [String]
        var weak: [String] = []
    }

    static func packs(forFolderNamed name: String) -> [Pack] {
        let nameTokens = tokenize(name, dropStopwords: true).map { ($0.norm, $0.stem) }
        guard !nameTokens.isEmpty else { return [] }
        return knowledge.filter { pack in
            pack.aliases.contains { alias in
                let a = normalize(alias)
                let s = stem(a)
                return nameTokens.contains { $0.0 == a || $0.1 == s || (a.count >= 4 && $0.0.hasPrefix(a)) }
            }
        }
    }

    static let knowledge: [Pack] = [
        Pack(aliases: ["arbeit", "job", "beruf", "work", "büro", "firma"],
             strong: ["arbeit", "job", "chef", "chefin", "kollege", "meeting", "besprechung", "büro", "projekt", "kunde",
                      "präsentation", "bericht", "schicht", "gehalt", "bewerbung", "vorstellungsgespräch", "baustelle",
                      "bauleiter", "bauleitung", "angebot", "auftrag", "firma", "dienstplan", "überstunden", "feierabend",
                      "vertrag", "teams", "outlook", "protokoll", "bautagesbericht", "werkstudent", "praktikum", "arbeitgeber"],
             weak: ["mail", "email", "anrufen", "termin", "deadline", "excel", "zeichnung", "plan", "rückmeldung"]),
        Pack(aliases: ["freizeit", "hobby", "hobbys", "spass", "fun"],
             strong: ["film", "serie", "netflix", "kino", "buch", "spiel", "zocken", "playstation", "konzert", "festival",
                      "urlaub", "reise", "ausflug", "wandern", "fahrrad", "radtour", "gym", "fitness", "training", "joggen",
                      "laufen", "schwimmen", "fußball", "sport", "musik", "gitarre", "klavier", "podcast", "youtube", "museum",
                      "strand", "camping", "hobby", "malen", "fotografieren", "spotify", "album", "gaming", "lesen"],
             weak: ["entspannen", "wochenende", "ausprobieren", "anschauen", "gucken", "schauen", "hören", "spaß"]),
        Pack(aliases: ["freunde", "freund", "freundeskreis", "friends", "leute", "sozial"],
             strong: ["freund", "freundin", "kumpel", "geburtstag", "party", "feier", "feiern", "verabreden", "treffen",
                      "grillen", "besuchen", "besuch", "mama", "papa", "mutter", "vater", "eltern", "oma", "opa", "bruder",
                      "schwester", "familie", "cousin", "cousine", "tante", "onkel", "hochzeit", "gratulieren", "whatsapp",
                      "jungs", "mädels"],
             weak: ["anrufen", "schreiben", "melden", "zurückrufen", "bier", "kneipe", "bar", "abend", "geschenk", "nachricht"]),
        Pack(aliases: ["aufgaben", "aufgabe", "todo", "todos", "tasks", "erledigen"],
             strong: ["erledigen", "abgeben", "beantragen", "anmelden", "abmelden", "kündigen", "bezahlen", "überweisen",
                      "unterschreiben", "ausfüllen", "formular", "antrag", "frist", "deadline", "einreichen", "zurückschicken",
                      "abholen", "besorgen", "reparieren", "buchen", "reservieren", "verlängern", "vereinbaren",
                      "organisieren", "erinnern", "ummelden", "zahlen", "rechnung", "steuer", "steuererklärung",
                      "versicherung", "arzt", "zahnarzt", "termin", "bewerben", "drucken", "scannen", "post", "paket"],
             weak: ["muss", "müssen", "sollte", "nicht vergessen", "vergessen", "dringend", "wichtig", "fertig",
                    "fertigstellen", "machen", "checken", "prüfen", "hausarbeit", "abgabe", "klausur", "referat", "lernen"]),
        Pack(aliases: ["haushalt", "wohnung", "zuhause", "home", "putzen", "wg"],
             strong: ["putzen", "sauber", "saubermachen", "waschen", "wäsche", "spülen", "abwasch", "spülmaschine",
                      "staubsaugen", "saugen", "wischen", "müll", "mülleimer", "altglas", "pfand", "aufräumen", "einkaufen",
                      "einkauf", "einkaufsliste", "supermarkt", "rewe", "edeka", "aldi", "lidl", "penny", "netto", "dm",
                      "rossmann", "kochen", "rezept", "küche", "bad", "badezimmer", "kühlschrank", "bettwäsche", "handtücher",
                      "pflanzen", "gießen", "miete", "nebenkosten", "strom", "handwerker", "vermieter", "glühbirne", "milch",
                      "brot", "eier", "butter", "käse", "nudeln", "obst", "gemüse", "klopapier", "toilettenpapier",
                      "spülmittel", "waschmittel", "zahnpasta", "duschgel", "shampoo", "kaffee", "getränke", "bügeln",
                      "fenster", "staub", "lebensmittel"],
             weak: ["kaufen", "holen", "besorgen", "leer", "kaputt", "wasser"]),
        // Wissen für häufige eigene Ordner
        Pack(aliases: ["uni", "universität", "studium", "hochschule", "hcu", "fh", "vorlesung", "semester", "schule", "studi"],
             strong: ["uni", "vorlesung", "seminar", "klausur", "prüfung", "hausarbeit", "abgabe", "professor", "prof",
                      "dozent", "modul", "semester", "bibliothek", "referat", "übung", "tutorium", "studium", "hcu",
                      "moodle", "credits", "bachelor", "master", "thesis", "bachelorarbeit", "masterarbeit", "mensa",
                      "lerngruppe", "skript", "lernen", "semesterarbeit", "bauko", "statik", "entwurf"],
             weak: ["zusammenfassung", "notizen", "gruppe", "lesen"]),
        Pack(aliases: ["sport", "fitness", "training", "gym", "workout"],
             strong: ["sport", "gym", "fitness", "training", "trainieren", "joggen", "laufen", "schwimmen", "fußball",
                      "radfahren", "fahrrad", "yoga", "workout", "krafttraining", "liegestütze", "marathon", "verein",
                      "tennis", "basketball", "volleyball", "klettern", "bouldern", "dehnen", "protein"],
             weak: ["kilometer", "muskeln", "ausdauer"]),
        Pack(aliases: ["finanzen", "geld", "finanz", "budget", "konto", "bank", "sparen"],
             strong: ["geld", "konto", "bank", "überweisen", "überweisung", "rechnung", "steuer", "steuererklärung",
                      "sparen", "budget", "versicherung", "kredit", "depot", "aktien", "etf", "miete", "gehalt", "bafög",
                      "paypal", "kosten", "ausgaben", "einnahmen", "zahlen", "bezahlen"],
             weak: ["euro", "preis", "teuer", "günstig"]),
        Pack(aliases: ["gesundheit", "arzt", "health", "medizin", "körper"],
             strong: ["arzt", "ärztin", "zahnarzt", "hausarzt", "arzttermin", "apotheke", "medikament", "tabletten",
                      "impfung", "krankenkasse", "physio", "physiotherapie", "gesund", "krank", "kopfschmerzen",
                      "vitamin", "blutbild", "therapie"],
             weak: ["schlaf", "trinken", "ernährung", "müde"]),
        Pack(aliases: ["ideen", "idee", "einfälle", "einfall", "brainstorming", "inspiration", "projekte"],
             strong: ["idee", "konzept", "projektidee", "erfindung", "geschäftsidee", "startup", "prototyp", "app",
                      "vielleicht", "könnte", "wäre", "entwickeln"],
             weak: ["irgendwann", "ausprobieren", "neues", "cool"]),
        Pack(aliases: ["geschenke", "geschenk", "geschenkideen", "geburtstage", "weihnachten"],
             strong: ["geschenk", "schenken", "geburtstag", "weihnachten", "gutschein", "überraschung", "jahrestag"],
             weak: ["kaufen", "bestellen", "amazon"]),
        Pack(aliases: ["reisen", "reise", "urlaub", "travel", "trip"],
             strong: ["urlaub", "reise", "reisen", "flug", "fliegen", "hotel", "airbnb", "bahn", "zug", "ticket",
                      "koffer", "packen", "reisepass", "strand", "städtetrip", "roadtrip", "camping"],
             weak: ["wochenende", "ausflug", "buchen"]),
        Pack(aliases: ["einkaufen", "einkauf", "einkaufsliste", "shopping", "supermarkt", "lebensmittel"],
             strong: ["kaufen", "einkaufen", "besorgen", "bestellen", "milch", "brot", "eier", "butter", "käse", "nudeln",
                      "obst", "gemüse", "klopapier", "kaffee", "getränke", "supermarkt", "rewe", "edeka", "aldi", "lidl", "dm"]),
        Pack(aliases: ["filme", "film", "serien", "serie", "watchlist", "medien"],
             strong: ["film", "serie", "netflix", "prime", "disney", "kino", "staffel", "folge", "anschauen", "gucken",
                      "doku", "trailer"]),
        Pack(aliases: ["bücher", "buch", "leseliste"],
             strong: ["buch", "lesen", "roman", "autor", "kindle", "hörbuch", "kapitel"]),
        Pack(aliases: ["musik", "music", "songs", "playlist"],
             strong: ["song", "lied", "album", "playlist", "spotify", "konzert", "band", "gitarre", "klavier", "üben"]),
        Pack(aliases: ["familie", "family", "eltern"],
             strong: ["mama", "papa", "mutter", "vater", "eltern", "oma", "opa", "bruder", "schwester", "familie",
                      "cousin", "cousine", "tante", "onkel", "nichte", "neffe"])
    ]
}
