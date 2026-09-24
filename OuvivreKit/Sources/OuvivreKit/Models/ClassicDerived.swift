import SwiftUI

/// A single weighted-criterion row (0...5), shared by the geo, meteo, and
/// per-group sliders — mirrors the dc export's `row()` helper.
public struct WeightedRow: Identifiable {
    public let id: Int
    public let label: String
    public let value: Int
    public let maxValue: Int
    public let tags: [String]

    public init(id: Int, label: String, value: Int, maxValue: Int = 5, tags: [String] = ClassicStatic.tags) {
        self.id = id
        self.label = label
        self.value = value
        self.maxValue = maxValue
        self.tags = tags
    }

    public var tag: String { tags[min(value, tags.count - 1)].uppercased() }
    public var pct: CGFloat { maxValue > 0 ? CGFloat(value) / CGFloat(maxValue) : 0 }
}

public struct NavItem: Identifiable {
    public var id: String { label }
    public let num: String
    public let label: String
    public let meta: String?
    public let screen: ClassicScreen
    public let active: Bool
}

/// All presentation-ready values derived from `ClassicState` — mirrors
/// `renderVals()` in the dc export.
@MainActor
public struct ClassicDerived {
    public let state: ClassicState
    public let theme: ClassicTheme

    /// Real département scores (weighted by `weights`, defaults to
    /// `state.geo`), ranked — backed by `FranceGeoData` (IGN-derived, see
    /// geo_pipeline/). Replaces the old fake `topScore = 60 + geoSum*1.6`
    /// formula. `excluding` drops criteria (by index into
    /// `FranceGeoData.criterionKeys`) from the average. Géographie 2 passes
    /// its own `state.geo2` (4-level scale) as `weights`.
    public func rankedDepartements(weights: [Int]? = nil, excluding: Set<Int> = [], maxWeight: Int = 5) -> [(dep: FranceGeoData.DepartementScore, score: Double)] {
        let weights = weights ?? state.geo
        // Hard-filtered criteria (see `FranceGeoData.hardFilterCriteria`) get
        // an eligibility floor on top of the weighted average below — a
        // weight alone can't make "déterminant" mean "only départements
        // that actually touch a coast/border".
        let hardFilterWeights: [(key: String, weight: Int)] = FranceGeoData.criterionKeys.enumerated().compactMap { i, key in
            guard FranceGeoData.hardFilterCriteria.contains(key), i < weights.count, !excluding.contains(i) else { return nil }
            return (key, weights[i])
        }
        // "pays étranger" gets its own km-based filter (see
        // `FranceGeoData.maxPaysEtrangerKm`) rather than the score-band one
        // above — its score is a compressed continuous distance, not a
        // handful of discrete buckets like "mer".
        let paysEtrangerIndex = FranceGeoData.criterionKeys.firstIndex(of: "paysEtranger")!
        let paysEtrangerWeight = (paysEtrangerIndex < weights.count && !excluding.contains(paysEtrangerIndex)) ? weights[paysEtrangerIndex] : 0
        let activeFilterCount = hardFilterWeights.filter { $0.weight > 0 }.count + (paysEtrangerWeight > 0 ? 1 : 0)
        let allowedMisses = FranceGeoData.allowedMisses(activeFilterCount: activeFilterCount)
        return FranceGeoData.departements
            .filter { !(state.excludeOverseas && $0.isOverseas) }
            .filter { !(state.excludeCorse && $0.isCorse) }
            // Un ou deux critères réglés s'appliquent en ET strict ; au-delà,
            // un raté est toléré (deux à partir de 5 critères), sinon leurs
            // exigences se concurrencent au point de tout éliminer — voir
            // `FranceGeoData.allowedMisses`.
            .filter { dep in
                let misses = hardFilterWeights.reduce(0) { count, entry in
                    FranceGeoData.passesHardFilter(dep, key: entry.key, weight: entry.weight, maxWeight: maxWeight) ? count : count + 1
                } + (FranceGeoData.passesPaysEtrangerFilter(dep, weight: paysEtrangerWeight, maxWeight: maxWeight) ? 0 : 1)
                return misses <= allowedMisses
            }
            .map { ($0, FranceGeoData.weightedScore($0, weights: weights, excluding: excluding)) }
            .sorted { $0.1 > $1.1 }
    }

    public var navSteps: [NavItem] {
        let defs: [(String, String, ClassicScreen, String?)] = [
            ("01d", "Sélecteur", .selecteur, nil)
        ]
        return defs.map { NavItem(num: $0.0, label: $0.1, meta: $0.3, screen: $0.2, active: state.screen == $0.2 && state.selectedDepartementCode == nil) }
    }

    public struct CountryChip: Identifiable { public var id: String { name }; public let name: String; public let selected: Bool }
    public var countryList: [CountryChip] {
        ClassicStatic.countries.map { CountryChip(name: $0, selected: $0 == state.country) }
    }

    public var countryFacts: [LabeledValue] {
        ClassicStatic.countryProfiles[state.country]?.facts ?? []
    }

    /// Géographie 2's rows, on its own 3-level (0...2) scale — "souhaitable" et "accessoire" fusionnés dans "important".
    public var geo2Rows: [WeightedRow] {
        ClassicStatic.geo.enumerated().map { WeightedRow(id: $0, label: $1.0, value: state.geo2[$0], maxValue: 2, tags: ClassicStatic.tagsGeo2) }
    }

    public struct DerivedGroup: Identifiable {
        public let id: Int
        public let title: String
        public let count: Int
        public let rows: [WeightedRow]
    }
    public var groups: [DerivedGroup] {
        ClassicStatic.groups.enumerated().map { gi, g in
            let rows = g.rows.enumerated().map { ri, r in WeightedRow(id: ri, label: r.0, value: state.groups[gi][ri]) }
            return DerivedGroup(id: gi, title: g.title, count: g.rows.count, rows: rows)
        }
    }

    /// Les 3 critères Culture repris par "Big Mac" (Musées, Lieux du
    /// patrimoine, Festivals) dont le réglage est au-dessus de 0 (différent
    /// d'"Indifférent"), avec la clé `CultureScores.criterionKeys`
    /// correspondante — utilisé par l'inspecteur pour lister les critères
    /// actifs et le contenu culturel du département cliqué.
    public var bigMacActiveCultureCriteria: [(label: String, key: String)] {
        guard let cultureGroup = groups.first(where: { $0.title == "CULTURE" }) else { return [] }
        let keyByLabel = ["Musées": "musees", "Lieux du patrimoine": "patrimoine", "Festivals": "festivals"]
        return cultureGroup.rows.compactMap { row -> (label: String, key: String)? in
            guard row.value > 0, let key = keyByLabel[row.label] else { return nil }
            return (row.label, key)
        }
    }
}
