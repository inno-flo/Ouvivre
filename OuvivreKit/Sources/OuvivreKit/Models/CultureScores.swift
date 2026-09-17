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
}
