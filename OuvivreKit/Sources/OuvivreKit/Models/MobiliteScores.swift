import Foundation

/// Real per-département 0-100 scores for the 2 Mobilité criteria kept in
/// "Big Mac" (Pistes cyclables, Gares), precomputed offline from
/// data.gouv.fr datasets — see geo_pipeline/build_mobilite_data.py and
/// geo_pipeline/README.md. Mirrors `CultureScores`'s loading pattern.
public enum MobiliteScores {
    public struct DepartementScore: Decodable {
        public let codeInsee: String
        public let nom: String
        public let scores: [String: Double]
        /// Noms des gares voyageurs par département ("gares" uniquement —
        /// "pistesCyclables" n'a pas de noms individuels, juste un linéaire).
        public let names: [String: [String]]

        enum CodingKeys: String, CodingKey { case codeInsee, nom, scores, names }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            codeInsee = try c.decode(String.self, forKey: .codeInsee)
            nom = try c.decode(String.self, forKey: .nom)
            scores = try c.decode([String: Double].self, forKey: .scores)
            names = try c.decodeIfPresent([String: [String]].self, forKey: .names) ?? [:]
        }
    }

    private struct Root: Decodable {
        let generatedAt: String
        let departements: [DepartementScore]
    }

    /// Stable key order, matching the 2 Mobilité rows kept in `BigMacView`.
    public static let criterionKeys = ["pistesCyclables", "gares"]

    private static let root: Root? = {
        guard let url = Bundle.module.url(forResource: "mobilite_scores", withExtension: "json"),
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

    /// Weighted match (0-100) of a département against 2 weights (0...5,
    /// same order as `criterionKeys`), by weighted average of its criterion
    /// scores — same convention as `CultureScores.weightedScore`. Missing
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
    /// (Pistes cyclables/Gares) is pushed to "déterminant" — see
    /// `passesHardFilter`.
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

    /// Noms des gares voyageurs pour un département donné — utilisé par
    /// l'inspecteur pour lister la desserte ferroviaire du département
    /// cliqué. `criterionKey` "pistesCyclables" renvoie toujours [].
    public static func names(forDepartementCode code: String, criterionKey: String) -> [String] {
        byDepartementCode[code]?.names[criterionKey] ?? []
    }
}
