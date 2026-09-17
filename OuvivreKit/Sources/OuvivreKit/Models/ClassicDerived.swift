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

    public var geoSum: Int { state.geo.reduce(0, +) }

    /// Real département scores (weighted by `weights`, defaults to
    /// `state.geo`), ranked — backed by `FranceGeoData` (IGN-derived, see
    /// geo_pipeline/). Replaces the old fake `topScore = 60 + geoSum*1.6`
    /// formula. `excluding` drops criteria (by index into
    /// `FranceGeoData.criterionKeys`) from the average. Géographie 2 passes
    /// its own `state.geo2` (5-level scale) as `weights`.
    public func rankedDepartements(weights: [Int]? = nil, excluding: Set<Int> = []) -> [(dep: FranceGeoData.DepartementScore, score: Double)] {
        let weights = weights ?? state.geo
        return FranceGeoData.departements
            .filter { !(state.excludeOverseas && $0.isOverseas) }
            .filter { !(state.excludeCorse && $0.isCorse) }
            .map { ($0, FranceGeoData.weightedScore($0, weights: weights, excluding: excluding)) }
            .sorted { $0.1 > $1.1 }
    }

    /// Régions ranked by the mean weighted score of their départements — the
    /// primary "région la plus probante" ranking is at région level, backed
    /// by a finer per-département computation (see plan: région ranking,
    /// département detail).
    public func rankedRegions(weights: [Int]? = nil, excluding: Set<Int> = []) -> [(nomRegion: String, score: Double, bestDept: FranceGeoData.DepartementScore)] {
        let ranked = rankedDepartements(weights: weights, excluding: excluding)
        var byRegion: [String: [(dep: FranceGeoData.DepartementScore, score: Double)]] = [:]
        for entry in ranked { byRegion[entry.dep.nomRegion, default: []].append(entry) }
        return byRegion.map { nomRegion, entries in
            let mean = entries.map(\.score).reduce(0, +) / Double(entries.count)
            let best = entries.max { $0.score < $1.score }!.dep
            return (nomRegion, mean, best)
        }.sorted { $0.score > $1.score }
    }

    public struct WinningRegion { public let nomRegion: String; public let bestDept: String; public let score: Int }
    public func winningRegion(weights: [Int]? = nil, excluding: Set<Int> = []) -> WinningRegion? {
        guard let top = rankedRegions(weights: weights, excluding: excluding).first else { return nil }
        return WinningRegion(nomRegion: top.nomRegion, bestDept: top.bestDept.nom, score: Int(top.score.rounded()))
    }
    public func topScore(weights: [Int]? = nil, excluding: Set<Int> = []) -> Int { winningRegion(weights: weights, excluding: excluding)?.score ?? 0 }

    public var navSteps: [NavItem] {
        let defs: [(String, String, ClassicScreen, String?)] = [
            ("01", "Pays", .pays, "France"),
            ("01b", "Régions", .geo2, nil),
            ("02", "Services", .affiner, "14"),
            ("04", "Climat", .meteo, "9")
        ]
        return defs.map { NavItem(num: $0.0, label: $0.1, meta: $0.3, screen: $0.2, active: state.screen == $0.2) }
    }

    public var navTools: [NavItem] {
        let defs: [(String, String, ClassicScreen)] = [
            ("05", "Fiche ville", .ville), ("06", "Comparateur", .compare), ("07", "Mon espace", .profil)
        ]
        return defs.map { NavItem(num: $0.0, label: $0.1, meta: nil, screen: $0.2, active: state.screen == $0.2) }
    }

    public struct CountryChip: Identifiable { public var id: String { name }; public let name: String; public let selected: Bool }
    public var countryList: [CountryChip] {
        ClassicStatic.countries.map { CountryChip(name: $0, selected: $0 == state.country) }
    }

    public var countryFacts: [LabeledValue] {
        ClassicStatic.countryProfiles[state.country]?.facts ?? []
    }
    public var countrySources: [ClassicStatic.CountrySource] {
        ClassicStatic.countryProfiles[state.country]?.sources ?? []
    }

    public var geoRows: [WeightedRow] {
        ClassicStatic.geo.enumerated().map { WeightedRow(id: $0, label: $1.0, value: state.geo[$0]) }
    }
    /// Géographie 2's rows, on its own 5-level (0...4) scale — no "prioritaire".
    public var geo2Rows: [WeightedRow] {
        ClassicStatic.geo.enumerated().map { WeightedRow(id: $0, label: $1.0, value: state.geo2[$0], maxValue: 4, tags: ClassicStatic.tagsGeo2) }
    }
    public var meteoRows: [WeightedRow] {
        ClassicStatic.meteo.enumerated().map { WeightedRow(id: $0, label: $1.0, value: state.meteo[$0]) }
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

    public struct RegionRow: Identifiable {
        public var id: String { name }
        public let rank: String
        public let name: String
        public let nomRegion: String
        public let score: Int
        public var pct: CGFloat { CGFloat(score) / 100 }
    }
    /// Top départements nationally by weighted score, skipping the one
    /// already shown as the winning région's headline pick.
    public func regionRows(weights: [Int]? = nil, excluding: Set<Int> = []) -> [RegionRow] {
        let bestDeptName = winningRegion(weights: weights, excluding: excluding)?.bestDept
        return rankedDepartements(weights: weights, excluding: excluding)
            .filter { $0.dep.nom != bestDeptName && $0.score >= 35 }
            .enumerated()
            .map { i, entry in RegionRow(rank: String(format: "%02d", i + 2), name: entry.dep.nom, nomRegion: entry.dep.nomRegion, score: Int(entry.score.rounded())) }
    }

    public struct CityCard: Identifiable {
        public var id: String { name }
        public let rank: String
        public let name: String
        public let sub: String
        public let score: Int
        public let inline: String
        public let bars: [(key: String, pct: CGFloat, v: Int)]
        public var scorePct: CGFloat { CGFloat(score) / 100 }
    }
    public var cities: [CityCard] {
        ClassicStatic.cities.enumerated().map { i, c in
            CityCard(
                rank: String(format: "%02d", i + 1), name: c.name, sub: c.sub, score: c.score, inline: c.inline,
                bars: c.bars.map { (key: $0.key, pct: CGFloat($0.value) / 100, v: $0.value) }
            )
        }
    }

    public var shortlist: [CityCard] { Array(cities.prefix(4)) }

    // MARK: Fiche ville (fixed: Annecy)

    public struct VilleFamilyDerived: Identifiable { public var id: String { key }; public let key: String; public let value: Int; public let note: String; public var pct: CGFloat { CGFloat(value) / 100 } }
    public struct MonthBar: Identifiable { public var id: Int { index }; public let index: Int; public let label: String; public let temp: Int; public var height: CGFloat { CGFloat(18 + Double(temp) * 3.6) } }

    public var villeFamilies: [VilleFamilyDerived] {
        ClassicStatic.ville.families.map { VilleFamilyDerived(key: $0.key, value: $0.value, note: $0.note) }
    }
    public var villeMonths: [MonthBar] {
        let letters = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        return ClassicStatic.ville.temps.enumerated().map { i, t in MonthBar(index: i, label: letters[i], temp: t) }
    }

    // MARK: Comparateur (fixed: top 3 cities)

    public struct CompareCell { public let value: String; public let best: Bool }
    public struct CompareRow: Identifiable { public var id: String { label }; public let label: String; public let cells: [CompareCell] }
    public var compareHeads: [(name: String, sub: String)] {
        ClassicStatic.cities.prefix(3).map { (name: $0.name, sub: String($0.sub.split(separator: "·").first ?? "").trimmingCharacters(in: .whitespaces).uppercased()) }
    }
    public var compareRows: [CompareRow] {
        ClassicStatic.compareData.map { label, vals, best in
            CompareRow(label: label, cells: vals.enumerated().map { i, v in CompareCell(value: v, best: i == best) })
        }
    }
    public var compareScores: [Int] { ClassicStatic.cities.prefix(3).map(\.score) }
}
