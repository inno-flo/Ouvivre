import Foundation

/// Real per-département proximity scores (0-100) for the 6 Géographie
/// criteria, precomputed offline from IGN (BD TOPO V3, RGE ALTI) and
/// Natural Earth data — see geo_pipeline/ at the repo root. Criterion order
/// matches `ClassicStatic.geo` (paysEtranger, mer, montagne, lacs, fleuves, forets).
public enum FranceGeoData {
    public struct DepartementScore: Decodable {
        public let codeInsee: String
        public let nom: String
        public let codeRegion: String
        public let nomRegion: String
        public let scores: [String: Double]

        public var isOverseas: Bool { codeInsee.hasPrefix("97") }
        public var isCorse: Bool { codeInsee == "2A" || codeInsee == "2B" }
    }

    private struct Root: Decodable {
        let departements: [DepartementScore]
    }

    /// Stable key order, matching `ClassicStatic.geo`'s 6 rows.
    public static let criterionKeys = ["paysEtranger", "mer", "montagne", "lacs", "fleuves", "forets"]

    public static let departements: [DepartementScore] = {
        guard let url = Bundle.module.url(forResource: "france_geo_scores", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else {
            return []
        }
        return root.departements
    }()

    /// Weighted match (0-100) of a département against 6 weights (0...5, same
    /// order as `criterionKeys`), by weighted average of its criterion scores.
    /// `excluding` drops criteria (by index into `criterionKeys`) from the
    /// average entirely, e.g. for Géographie 2's 5-criteria variant.
    public static func weightedScore(_ dep: DepartementScore, weights: [Int], excluding: Set<Int> = []) -> Double {
        var weightedSum = 0.0
        var weightTotal = 0.0
        for (i, key) in criterionKeys.enumerated() where i < weights.count && !excluding.contains(i) {
            let w = Double(weights[i])
            weightedSum += w * (dep.scores[key] ?? 50.0)
            weightTotal += w
        }
        return weightTotal > 0 ? weightedSum / weightTotal : 50.0
    }
}
