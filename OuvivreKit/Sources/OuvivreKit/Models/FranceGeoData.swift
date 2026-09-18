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

    /// Criteria that get a hard eligibility filter on top of the usual
    /// weighted-average blend, indexed into `criterionKeys` — "mer" and
    /// "paysEtranger". Both are nominally continuous distance scores, but
    /// each has a real geographic "hop 0" that a weighted average alone
    /// can't privilege enough:
    /// - "mer" is actually computed as a hop-count to the nearest coastal
    ///   département, quantized into 5 buckets (0/25/50/75/100 — see
    ///   geo_pipeline/recompute_mer_score.py). Blending it lets an inland
    ///   département 2 hops from the coast (e.g. Loire, Marne — score 50)
    ///   outrank a truly coastal one once other criteria tip the average.
    /// - "paysEtranger" is a genuine km distance, but min-max normalized
    ///   against the full 101-département range (stretched by the very
    ///   distant DROM), which compresses mainland distances: a département
    ///   5 km from a border (not touching it) still scores ~98, barely
    ///   below the 23 départements that actually share a border (score
    ///   exactly 100.0, since only they have raw distance 0 — see
    ///   geo_pipeline/build_france_geo_scores.py:311-316). So "déterminant"
    ///   on the slider let near-miss départements through as if they
    ///   touched a border, and with no other criterion active and a wide
    ///   commune-size filter, that reads as "almost every département
    ///   matches".
    /// Both symptoms are the same shape — "déterminant" should mean what it
    /// says instead of just tipping a weighted average — so both get the
    /// same fix: a hard floor on the raw score, not just a weight in the
    /// average.
    public static let hardFilterCriteria: Set<String> = ["mer", "paysEtranger"]

    /// Minimum raw score (0-100) a département must have on a hard-filtered
    /// criterion to pass at this slider weight — `nil` means no filter
    /// (weight 0, "indifférent"). Each step up raises the floor by 25
    /// points, the same bucket width "mer"'s hop-count is already quantized
    /// into: weight 1 ("souhaitable") -> 50, 2 ("important") -> 75, 3
    /// ("déterminant") -> 100 — which for "mer" means hop 0 exactly, and for
    /// "paysEtranger" means the raw distance is exactly 0 (a real border),
    /// since only those départements reach a score of precisely 100.
    public static func minHardFilterScore(forWeight weight: Int) -> Double? {
        guard weight > 0 else { return nil }
        return Double(25 * (weight + 1))
    }

    /// Whether `dep` passes the hard filter for `key` at `weight` (see
    /// `minHardFilterScore`). Criteria not in `hardFilterCriteria` always
    /// pass — they stay purely a weight in `weightedScore`'s average.
    public static func passesHardFilter(_ dep: DepartementScore, key: String, weight: Int) -> Bool {
        guard hardFilterCriteria.contains(key), let minScore = minHardFilterScore(forWeight: weight) else { return true }
        return (dep.scores[key] ?? 50.0) >= minScore
    }
}
