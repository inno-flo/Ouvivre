import Foundation
import CoreLocation

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

    /// Position (centre de la commune) de chaque chef-lieu, par code INSEE de
    /// département — source : API officielle geo.api.gouv.fr (contours
    /// communaux de l'IGN), relevée une fois et figée ici.
    public static let chefsLieuxCoordinates: [String: CLLocationCoordinate2D] = [
        "01": CLLocationCoordinate2D(latitude: 46.2027, longitude: 5.2469),
        "02": CLLocationCoordinate2D(latitude: 49.5711, longitude: 3.6130),
        "03": CLLocationCoordinate2D(latitude: 46.5591, longitude: 3.3255),
        "04": CLLocationCoordinate2D(latitude: 44.0954, longitude: 6.2495),
        "05": CLLocationCoordinate2D(latitude: 44.5797, longitude: 6.0616),
        "06": CLLocationCoordinate2D(latitude: 43.7032, longitude: 7.2528),
        "07": CLLocationCoordinate2D(latitude: 44.7214, longitude: 4.5949),
        "08": CLLocationCoordinate2D(latitude: 49.7802, longitude: 4.7304),
        "09": CLLocationCoordinate2D(latitude: 42.9701, longitude: 1.6090),
        "10": CLLocationCoordinate2D(latitude: 48.2924, longitude: 4.0761),
        "11": CLLocationCoordinate2D(latitude: 43.2078, longitude: 2.3491),
        "12": CLLocationCoordinate2D(latitude: 44.3591, longitude: 2.5699),
        "13": CLLocationCoordinate2D(latitude: 43.2803, longitude: 5.3806),
        "14": CLLocationCoordinate2D(latitude: 49.1846, longitude: -0.3722),
        "15": CLLocationCoordinate2D(latitude: 44.9281, longitude: 2.4416),
        "16": CLLocationCoordinate2D(latitude: 45.6458, longitude: 0.1450),
        "17": CLLocationCoordinate2D(latitude: 46.1620, longitude: -1.1765),
        "18": CLLocationCoordinate2D(latitude: 47.0780, longitude: 2.3983),
        "19": CLLocationCoordinate2D(latitude: 45.2685, longitude: 1.7663),
        "2A": CLLocationCoordinate2D(latitude: 41.9228, longitude: 8.7058),
        "2B": CLLocationCoordinate2D(latitude: 42.6861, longitude: 9.4240),
        "21": CLLocationCoordinate2D(latitude: 47.3319, longitude: 5.0322),
        "22": CLLocationCoordinate2D(latitude: 48.5108, longitude: -2.7657),
        "23": CLLocationCoordinate2D(latitude: 46.1585, longitude: 1.8705),
        "24": CLLocationCoordinate2D(latitude: 45.1939, longitude: 0.7105),
        "25": CLLocationCoordinate2D(latitude: 47.2602, longitude: 6.0123),
        "26": CLLocationCoordinate2D(latitude: 44.9234, longitude: 4.9164),
        "27": CLLocationCoordinate2D(latitude: 49.0180, longitude: 1.1406),
        "28": CLLocationCoordinate2D(latitude: 48.4481, longitude: 1.5046),
        "29": CLLocationCoordinate2D(latitude: 47.9982, longitude: -4.0972),
        "30": CLLocationCoordinate2D(latitude: 43.8322, longitude: 4.3429),
        "31": CLLocationCoordinate2D(latitude: 43.6007, longitude: 1.4328),
        "32": CLLocationCoordinate2D(latitude: 43.6602, longitude: 0.5673),
        "33": CLLocationCoordinate2D(latitude: 44.8624, longitude: -0.5848),
        "34": CLLocationCoordinate2D(latitude: 43.6100, longitude: 3.8742),
        "35": CLLocationCoordinate2D(latitude: 48.1159, longitude: -1.6884),
        "36": CLLocationCoordinate2D(latitude: 46.8023, longitude: 1.6903),
        "37": CLLocationCoordinate2D(latitude: 47.3943, longitude: 0.6949),
        "38": CLLocationCoordinate2D(latitude: 45.1842, longitude: 5.7155),
        "39": CLLocationCoordinate2D(latitude: 46.6758, longitude: 5.5574),
        "40": CLLocationCoordinate2D(latitude: 43.8931, longitude: -0.5009),
        "41": CLLocationCoordinate2D(latitude: 47.5813, longitude: 1.3049),
        "42": CLLocationCoordinate2D(latitude: 45.4241, longitude: 4.3665),
        "43": CLLocationCoordinate2D(latitude: 45.0283, longitude: 3.8973),
        "44": CLLocationCoordinate2D(latitude: 47.2382, longitude: -1.5603),
        "45": CLLocationCoordinate2D(latitude: 47.8734, longitude: 1.9122),
        "46": CLLocationCoordinate2D(latitude: 44.4565, longitude: 1.4390),
        "47": CLLocationCoordinate2D(latitude: 44.2010, longitude: 0.6302),
        "48": CLLocationCoordinate2D(latitude: 44.5349, longitude: 3.4909),
        "49": CLLocationCoordinate2D(latitude: 47.4819, longitude: -0.5629),
        "50": CLLocationCoordinate2D(latitude: 49.1123, longitude: -1.0812),
        "51": CLLocationCoordinate2D(latitude: 48.9656, longitude: 4.3801),
        "52": CLLocationCoordinate2D(latitude: 48.0965, longitude: 5.1566),
        "53": CLLocationCoordinate2D(latitude: 48.0578, longitude: -0.7692),
        "54": CLLocationCoordinate2D(latitude: 48.6881, longitude: 6.1734),
        "55": CLLocationCoordinate2D(latitude: 48.7628, longitude: 5.1732),
        "56": CLLocationCoordinate2D(latitude: 47.6577, longitude: -2.7485),
        "57": CLLocationCoordinate2D(latitude: 49.1048, longitude: 6.1962),
        "58": CLLocationCoordinate2D(latitude: 46.9852, longitude: 3.1598),
        "59": CLLocationCoordinate2D(latitude: 50.6311, longitude: 3.0468),
        "60": CLLocationCoordinate2D(latitude: 49.4425, longitude: 2.0877),
        "61": CLLocationCoordinate2D(latitude: 48.4310, longitude: 0.0923),
        "62": CLLocationCoordinate2D(latitude: 50.2893, longitude: 2.7679),
        "63": CLLocationCoordinate2D(latitude: 45.7870, longitude: 3.1127),
        "64": CLLocationCoordinate2D(latitude: 43.3219, longitude: -0.3435),
        "65": CLLocationCoordinate2D(latitude: 43.2387, longitude: 0.0653),
        "66": CLLocationCoordinate2D(latitude: 42.6990, longitude: 2.9045),
        "67": CLLocationCoordinate2D(latitude: 48.5691, longitude: 7.7621),
        "68": CLLocationCoordinate2D(latitude: 48.1115, longitude: 7.3924),
        "69": CLLocationCoordinate2D(latitude: 45.7580, longitude: 4.8351),
        "70": CLLocationCoordinate2D(latitude: 47.6323, longitude: 6.1523),
        "71": CLLocationCoordinate2D(latitude: 46.3265, longitude: 4.8083),
        "72": CLLocationCoordinate2D(latitude: 47.9819, longitude: 0.1957),
        "73": CLLocationCoordinate2D(latitude: 45.5822, longitude: 5.9064),
        "74": CLLocationCoordinate2D(latitude: 45.9024, longitude: 6.1264),
        "75": CLLocationCoordinate2D(latitude: 48.8589, longitude: 2.3470),
        "76": CLLocationCoordinate2D(latitude: 49.4412, longitude: 1.0912),
        "77": CLLocationCoordinate2D(latitude: 48.5421, longitude: 2.6552),
        "78": CLLocationCoordinate2D(latitude: 48.8039, longitude: 2.1191),
        "79": CLLocationCoordinate2D(latitude: 46.3274, longitude: -0.4613),
        "80": CLLocationCoordinate2D(latitude: 49.8987, longitude: 2.2847),
        "81": CLLocationCoordinate2D(latitude: 43.9290, longitude: 2.1323),
        "82": CLLocationCoordinate2D(latitude: 44.0217, longitude: 1.3646),
        "83": CLLocationCoordinate2D(latitude: 43.1364, longitude: 5.9334),
        "84": CLLocationCoordinate2D(latitude: 43.9416, longitude: 4.8333),
        "85": CLLocationCoordinate2D(latitude: 46.6659, longitude: -1.4162),
        "86": CLLocationCoordinate2D(latitude: 46.5846, longitude: 0.3715),
        "87": CLLocationCoordinate2D(latitude: 45.8567, longitude: 1.2260),
        "88": CLLocationCoordinate2D(latitude: 48.1637, longitude: 6.4867),
        "89": CLLocationCoordinate2D(latitude: 47.7939, longitude: 3.5821),
        "90": CLLocationCoordinate2D(latitude: 47.6458, longitude: 6.8410),
        "91": CLLocationCoordinate2D(latitude: 48.6287, longitude: 2.4313),
        "92": CLLocationCoordinate2D(latitude: 48.8974, longitude: 2.2018),
        "93": CLLocationCoordinate2D(latitude: 48.9073, longitude: 2.4432),
        "94": CLLocationCoordinate2D(latitude: 48.7845, longitude: 2.4523),
        "95": CLLocationCoordinate2D(latitude: 49.0373, longitude: 2.0455),
        "971": CLLocationCoordinate2D(latitude: 15.9992, longitude: -61.7294),
        "972": CLLocationCoordinate2D(latitude: 14.6492, longitude: -61.0686),
        "973": CLLocationCoordinate2D(latitude: 4.9464, longitude: -52.3319),
        "974": CLLocationCoordinate2D(latitude: -20.9434, longitude: 55.4444),
        "976": CLLocationCoordinate2D(latitude: -12.7875, longitude: 45.1964),
    ]
}
