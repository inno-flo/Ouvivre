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

    /// Criteria that get a hard eligibility filter on top of the usual
    /// weighted-average blend, indexed into `criterionKeys` — every geo
    /// criterion except "paysEtranger" (it has its own km-based filter
    /// below, see `maxPaysEtrangerKm`: unlike the others its score is a
    /// genuine but *compressed* continuous distance, so a score-band floor
    /// doesn't line up with real-world closeness the way it does here).
    /// Fires only at "déterminant" (see `passesHardFilter`'s `maxWeight`) —
    /// the whole point is that "déterminant" means AND/must-have, while
    /// "important" stays a pure weight in the average.
    public static let hardFilterCriteria: Set<String> = ["mer", "montagne", "lacs", "fleuves", "forets"]

    /// Per-criterion floor a département must clear to pass its hard filter
    /// at "déterminant" — the 85th percentile of that criterion's real
    /// score distribution across the 101 départements, i.e. only the top
    /// ~15% pass. A fixed floor (e.g. "score == 100") works for "mer" (a
    /// hop-count quantized into 5 buckets) but leaves almost nothing for
    /// continuous criteria like "forets" or "lacs" where near-101 depts sit
    /// well under 100 — the percentile keeps "déterminant" meaningfully
    /// strict without emptying the result for every criterion but "mer".
    public static func hardFilterThreshold(forKey key: String) -> Double? {
        guard hardFilterCriteria.contains(key) else { return nil }
        let values = departements.compactMap { $0.scores[key] }.sorted()
        guard !values.isEmpty else { return nil }
        let index = min(values.count - 1, Int((Double(values.count) * 0.85).rounded(.down)))
        return values[index]
    }

    /// Whether `dep` passes the hard filter for `key` at `weight` — only
    /// engages once `weight` reaches `maxWeight` (the slider's top value,
    /// "déterminant"); anything below stays a pure weight in
    /// `weightedScore`'s average. Criteria not in `hardFilterCriteria`
    /// always pass.
    public static func passesHardFilter(_ dep: DepartementScore, key: String, weight: Int, maxWeight: Int) -> Bool {
        guard maxWeight > 0, weight >= maxWeight, let threshold = hardFilterThreshold(forKey: key) else { return true }
        return (dep.scores[key] ?? 50.0) >= threshold
    }

    /// Max real-world distance (km) to the nearest foreign country — land
    /// border or short sea crossing alike, since that's exactly what
    /// `distancesKm["paysEtranger"]` already measures (build_france_geo_scores.py
    /// picks whichever neighboring country, e.g. the UK across the Manche,
    /// is geometrically nearest, regardless of land vs. sea). Only engages
    /// at "déterminant" (`weight >= maxWeight`), same AND/must-have rule as
    /// `passesHardFilter` — 30 km already covers every land border (0 km)
    /// plus the closest sea crossings (Pas-de-Calais 5 km from Belgium,
    /// Manche 22 km from Jersey).
    public static func maxPaysEtrangerKm(forWeight weight: Int, maxWeight: Int) -> Double? {
        guard maxWeight > 0, weight >= maxWeight else { return nil }
        return 30
    }

    /// Whether `dep` passes the "pays étranger" km filter for `weight` (see
    /// `maxPaysEtrangerKm`). Falls back to passing when the raw distance is
    /// missing (shouldn't happen — every département has one).
    public static func passesPaysEtrangerFilter(_ dep: DepartementScore, weight: Int, maxWeight: Int) -> Bool {
        guard let maxKm = maxPaysEtrangerKm(forWeight: weight, maxWeight: maxWeight) else { return true }
        guard let km = dep.distancesKm["paysEtranger"] else { return true }
        return km <= maxKm
    }

    /// Chef-lieu (préfecture) de chaque département, par code INSEE —
    /// géographie officielle établie, liste statique (aucune donnée de ce
    /// type dans `france_geo_scores.json` ni ailleurs dans le pipeline).
    public static let chefsLieux: [String: String] = [
        "01": "Bourg-en-Bresse", "02": "Laon", "03": "Moulins", "04": "Digne-les-Bains",
        "05": "Gap", "06": "Nice", "07": "Privas", "08": "Charleville-Mézières",
        "09": "Foix", "10": "Troyes", "11": "Carcassonne", "12": "Rodez",
        "13": "Marseille", "14": "Caen", "15": "Aurillac", "16": "Angoulême",
        "17": "La Rochelle", "18": "Bourges", "19": "Tulle", "2A": "Ajaccio",
        "2B": "Bastia", "21": "Dijon", "22": "Saint-Brieuc", "23": "Guéret",
        "24": "Périgueux", "25": "Besançon", "26": "Valence", "27": "Évreux",
        "28": "Chartres", "29": "Quimper", "30": "Nîmes", "31": "Toulouse",
        "32": "Auch", "33": "Bordeaux", "34": "Montpellier", "35": "Rennes",
        "36": "Châteauroux", "37": "Tours", "38": "Grenoble", "39": "Lons-le-Saunier",
        "40": "Mont-de-Marsan", "41": "Blois", "42": "Saint-Étienne", "43": "Le Puy-en-Velay",
        "44": "Nantes", "45": "Orléans", "46": "Cahors", "47": "Agen",
        "48": "Mende", "49": "Angers", "50": "Saint-Lô", "51": "Châlons-en-Champagne",
        "52": "Chaumont", "53": "Laval", "54": "Nancy", "55": "Bar-le-Duc",
        "56": "Vannes", "57": "Metz", "58": "Nevers", "59": "Lille",
        "60": "Beauvais", "61": "Alençon", "62": "Arras", "63": "Clermont-Ferrand",
        "64": "Pau", "65": "Tarbes", "66": "Perpignan", "67": "Strasbourg",
        "68": "Colmar", "69": "Lyon", "70": "Vesoul", "71": "Mâcon",
        "72": "Le Mans", "73": "Chambéry", "74": "Annecy", "75": "Paris",
        "76": "Rouen", "77": "Melun", "78": "Versailles", "79": "Niort",
        "80": "Amiens", "81": "Albi", "82": "Montauban", "83": "Toulon",
        "84": "Avignon", "85": "La Roche-sur-Yon", "86": "Poitiers", "87": "Limoges",
        "88": "Épinal", "89": "Auxerre", "90": "Belfort", "91": "Évry-Courcouronnes",
        "92": "Nanterre", "93": "Bobigny", "94": "Créteil", "95": "Cergy",
        "971": "Basse-Terre", "972": "Fort-de-France", "973": "Cayenne",
        "974": "Saint-Denis", "976": "Mamoudzou",
    ]
}
