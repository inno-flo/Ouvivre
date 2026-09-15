import SwiftUI

/// A single weighted-criterion row (0...5), shared by the geo, meteo, and
/// per-group sliders — mirrors the dc export's `row()` helper.
public struct WeightedRow: Identifiable {
    public let id: Int
    public let label: String
    public let value: Int
    public var tag: String { ClassicStatic.tags[value].uppercased() }
    public var pct: CGFloat { CGFloat(value) / 5 }
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
    public var topScore: Int { min(99, 60 + Int((Double(geoSum) * 1.6).rounded())) }

    public var navSteps: [NavItem] {
        let defs: [(String, String, ClassicScreen, String)] = [
            ("01", "Pays", .pays, "France"), ("02", "Géographie", .geo, "5"),
            ("03", "Météo", .meteo, "9"), ("04", "Affiner", .affiner, "14")
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

    public var geoRows: [WeightedRow] {
        ClassicStatic.geo.enumerated().map { WeightedRow(id: $0, label: $1.0, value: state.geo[$0]) }
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

    public struct RegionRow: Identifiable { public var id: String { name }; public let rank: String; public let name: String; public let score: Int; public var pct: CGFloat { CGFloat(score) / 100 } }
    public var regionRows: [RegionRow] {
        ClassicStatic.regions.enumerated().map { i, r in RegionRow(rank: String(format: "%02d", i + 2), name: r.0, score: r.1) }
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
