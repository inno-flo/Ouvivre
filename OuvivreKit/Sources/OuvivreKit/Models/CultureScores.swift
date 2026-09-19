import Foundation

/// Real per-département 0-100 scores for the 3 Culture criteria kept in
/// "Big Mac" (Musées, Lieux du patrimoine, Festivals), precomputed offline
/// from culture.data.gouv.fr datasets — see geo_pipeline/build_culture_data.py
/// and geo_pipeline/README.md. Mirrors `FranceGeoData`'s loading pattern.
public enum CultureScores {
    public struct DepartementScore: Decodable {
        public let codeInsee: String
        public let nom: String
        public let scores: [String: Double]
        /// Noms des sites/événements par critère ("musees", "patrimoine",
        /// "festivals") — absent des JSON générés avant l'ajout de ce champ,
        /// d'où le `?` et le fallback à `[:]` au décodage.
        public let names: [String: [String]]
        /// Site officiel par critère puis par nom ("festivals" seulement :
        /// les données Basilic (musées) et SPR n'ont pas de site internet).
        public let urls: [String: [String: String]]
        /// Discipline dominante par critère puis par nom ("festivals"
        /// seulement : les musées n'ont pas de variable thématique).
        public let disciplines: [String: [String: String]]

        enum CodingKeys: String, CodingKey { case codeInsee, nom, scores, names, urls, disciplines }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            codeInsee = try c.decode(String.self, forKey: .codeInsee)
            nom = try c.decode(String.self, forKey: .nom)
            scores = try c.decode([String: Double].self, forKey: .scores)
            names = try c.decodeIfPresent([String: [String]].self, forKey: .names) ?? [:]
            urls = try c.decodeIfPresent([String: [String: String]].self, forKey: .urls) ?? [:]
            disciplines = try c.decodeIfPresent([String: [String: String]].self, forKey: .disciplines) ?? [:]
        }
    }

    private struct Root: Decodable {
        let generatedAt: String
        let departements: [DepartementScore]
    }

    /// Stable key order, matching the 3 Culture rows kept in `BigMacView`.
    public static let criterionKeys = ["musees", "patrimoine", "festivals"]

    private static let root: Root? = {
        guard let url = Bundle.module.url(forResource: "culture_scores", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Root.self, from: data)
    }()

    public static let departements: [DepartementScore] = root?.departements ?? []

    public static let generatedAt: String? = root?.generatedAt

    /// Scores indexed by département code — avoids a linear scan of the 101
    /// départements for every lookup when combining with commune-size
    /// matching in `BigMacView`.
    public static let byDepartementCode: [String: DepartementScore] = {
        Dictionary(uniqueKeysWithValues: departements.map { ($0.codeInsee, $0) })
    }()

    /// Weighted match (0-100) of a département against 3 weights (0...5,
    /// same order as `criterionKeys`), by weighted average of its criterion
    /// scores — same convention as `FranceGeoData.weightedScore`. Missing
    /// data (no bundled score for that département) falls back to 50.0.
    public static func weightedScore(forDepartementCode code: String, weights: [Int]) -> Double {
        guard let dep = byDepartementCode[code] else { return 50.0 }
        var weightedSum = 0.0
        var weightTotal = 0.0
        for (i, key) in criterionKeys.enumerated() where i < weights.count {
            let w = Double(weights[i])
            weightedSum += w * (dep.scores[key] ?? 50.0)
            weightTotal += w
        }
        return weightTotal > 0 ? weightedSum / weightTotal : 50.0
    }

    /// Floor a département must clear on `key` to pass its hard filter at
    /// "déterminant" — the 85th percentile of that criterion's real score
    /// distribution, same convention as `FranceGeoData.hardFilterThreshold`.
    /// Only the top ~15% of départements pass once a Big Mac criterion
    /// (Musées/Lieux du patrimoine/Festivals) is pushed to "déterminant" —
    /// see `passesHardFilter`.
    public static func hardFilterThreshold(forKey key: String) -> Double? {
        let values = departements.compactMap { $0.scores[key] }.sorted()
        guard !values.isEmpty else { return nil }
        let index = min(values.count - 1, Int((Double(values.count) * 0.85).rounded(.down)))
        return values[index]
    }

    /// Whether the département at `code` passes the hard filter for `key`
    /// at `weight` — only engages once `weight` reaches `maxWeight` (the
    /// slider's top value, "déterminant"); below that it's a pure weight in
    /// `weightedScore`'s average, same AND/must-have rule as
    /// `FranceGeoData.passesHardFilter`.
    public static func passesHardFilter(forDepartementCode code: String, key: String, weight: Int, maxWeight: Int) -> Bool {
        guard maxWeight > 0, weight >= maxWeight, let threshold = hardFilterThreshold(forKey: key), let dep = byDepartementCode[code] else { return true }
        return (dep.scores[key] ?? 50.0) >= threshold
    }

    /// Noms des sites/événements d'un critère ("musees", "patrimoine",
    /// "festivals") pour un département donné — utilisé par l'inspecteur
    /// pour lister le contenu culturel du département cliqué.
    public static func names(forDepartementCode code: String, criterionKey: String) -> [String] {
        byDepartementCode[code]?.names[criterionKey] ?? []
    }

    /// Site officiel d'un site/événement, si les données sources en fournissent un.
    public static func url(forDepartementCode code: String, criterionKey: String, name: String) -> URL? {
        byDepartementCode[code]?.urls[criterionKey]?[name].flatMap(URL.init(string:))
    }

    /// Discipline dominante d'un festival, si renseignée dans les données.
    public static func discipline(forDepartementCode code: String, criterionKey: String, name: String) -> String? {
        byDepartementCode[code]?.disciplines[criterionKey]?[name]
    }
}
