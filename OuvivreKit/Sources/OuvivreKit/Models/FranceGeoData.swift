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
        /// Raw (non-normalized) distances in km, currently just
        /// "paysEtranger" — see `add_pays_etranger_km.py`. Absent for
        /// criteria that don't need a real-world unit for filtering.
        public let distancesKm: [String: Double]

        private enum CodingKeys: String, CodingKey { case codeInsee, nom, codeRegion, nomRegion, scores, distancesKm }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            codeInsee = try c.decode(String.self, forKey: .codeInsee)
            nom = try c.decode(String.self, forKey: .nom)
            codeRegion = try c.decode(String.self, forKey: .codeRegion)
            nomRegion = try c.decode(String.self, forKey: .nomRegion)
            scores = try c.decode([String: Double].self, forKey: .scores)
            distancesKm = try c.decodeIfPresent([String: Double].self, forKey: .distancesKm) ?? [:]
        }

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

    /// Criteria that get a hard score-band eligibility filter on top of the
    /// usual weighted-average blend, indexed into `criterionKeys` — just
    /// "mer": it's computed as a hop-count to the nearest coastal
    /// département, quantized into 5 buckets (0/25/50/75/100 — see
    /// geo_pipeline/recompute_mer_score.py). Blending it lets an inland
    /// département 2 hops from the coast (e.g. Loire, Marne — score 50)
    /// outrank a truly coastal one once other criteria tip the average, so
    /// "déterminant" needs a hard floor, not just a weight in the average.
    /// ("paysEtranger" has its own km-based filter below — see
    /// `maxPaysEtrangerKm` — because unlike "mer" its score is a genuine
    /// but *compressed* continuous distance, not a handful of discrete
    /// buckets, so a score-band floor doesn't line up with real-world
    /// closeness the way it does for "mer".)
    public static let hardFilterCriteria: Set<String> = ["mer"]

    /// Minimum raw score (0-100) a département must have on a hard-filtered
    /// criterion to pass at this slider weight — `nil` means no filter
    /// (weight 0, "indifférent"). Each step up raises the floor by 25
    /// points, the same bucket width "mer"'s hop-count is already quantized
    /// into: weight 1 ("souhaitable") -> 50, 2 ("important") -> 75, 3
    /// ("déterminant") -> 100, i.e. hop 0 exactly.
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

    /// Max real-world distance (km) to the nearest foreign country — land
    /// border or short sea crossing alike, since that's exactly what
    /// `distancesKm["paysEtranger"]` already measures (build_france_geo_scores.py
    /// picks whichever neighboring country, e.g. the UK across the Manche,
    /// is geometrically nearest, regardless of land vs. sea) — a
    /// département may have and still pass the "pays étranger" filter at
    /// this slider weight. `nil` means no filter (weight 0, "indifférent").
    /// Thresholds are picked off the real distribution of distances (not
    /// the compressed score): 30 km already covers every land border (0 km)
    /// plus the closest sea crossings (Pas-de-Calais 5 km from Belgium,
    /// Manche 22 km from Jersey); 100 km adds the next tier (e.g.
    /// Seine-Maritime, ~100 km from the UK across the Manche); 250 km is a
    /// loose "not too far from a border" cutoff for the weakest setting.
    public static func maxPaysEtrangerKm(forWeight weight: Int) -> Double? {
        switch weight {
        case ..<1: return nil
        case 1: return 250
        case 2: return 100
        default: return 30
        }
    }

    /// Whether `dep` passes the "pays étranger" km filter for `weight` (see
    /// `maxPaysEtrangerKm`). Falls back to passing when the raw distance is
    /// missing (shouldn't happen — every département has one).
    public static func passesPaysEtrangerFilter(_ dep: DepartementScore, weight: Int) -> Bool {
        guard let maxKm = maxPaysEtrangerKm(forWeight: weight) else { return true }
        guard let km = dep.distancesKm["paysEtranger"] else { return true }
        return km <= maxKm
    }
}
