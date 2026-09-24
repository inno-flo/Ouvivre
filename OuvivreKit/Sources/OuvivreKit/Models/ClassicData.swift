import Foundation

public struct LabeledValue: Identifiable, Hashable {
    public var id: String { key }
    public let key: String
    public let value: String
    public init(_ key: String, _ value: String) { self.key = key; self.value = value }
}

/// Static reference data — mirrors the JS constants at the top of the dc export.
public enum ClassicStatic {
    public static let geo: [(String, Int)] = [
        ("Pays étranger", 2),
        ("Mer ou océan", 1),
        ("Montagne", 5),
        ("Lacs", 5),
        ("Fleuves et rivières", 3),
        ("Parcs et forêts", 4)
    ]
    /// Icône SF Symbols de chaque critère, indexée par son libellé —
    /// partagée par le tableau Favoris et les réglettes du Sélecteur.
    public static let criterionIcons: [String: String] = [
        "Chef-lieu": "mappin.and.ellipse",
        "Pays étranger": "globe.desk",
        "Mer ou océan": "figure.sailing",
        "Montagne": "mountain.2",
        "Lacs": "water.waves",
        "Fleuves et rivières": "figure.fishing",
        "Parcs et forêts": "tree",
        "Musées": "photo.artframe",
        "Lieux du patrimoine": "building.classical.columns",
        "Festivals": "fireworks",
        "Température moyenne": "thermometer.medium",
        "Température maximale moyenne": "thermometer.high",
        "Précipitations annuelles": "cloud.rain"
    ]

    public struct Group {
        public let title: String
        public let rows: [(String, Int)]
    }
    public static let groups: [Group] = [
        Group(title: "CULTURE", rows: [("Musées", 4), ("Équipements culturels", 3), ("Lieux du patrimoine", 4), ("Centre ancien", 5), ("Événements annuels", 3), ("Festivals", 3), ("Salons", 1)]),
        Group(title: "TAILLE", rows: [("Superficie de la ville", 2), ("Nombre d'habitants", 3)]),
        Group(title: "QUALITÉ DE VIE", rows: [("Classements de livabilité", 4)])
    ]

    public static let countries = ["France", "Danemark", "Suède", "Japon"]
    public static let tags = ["indifférent", "accessoire", "souhaitable", "important", "prioritaire", "déterminant"]
    /// Géographie 2's 3-level scale (0...2) — "accessoire", "souhaitable" et "prioritaire" fusionnés dans "important".
    public static let tagsGeo2 = ["indifférent", "important", "déterminant"]


    public struct CountrySource: Identifiable { public var id: String { label }; public let label: String; public let url: String }
    public struct CountryProfile {
        public let facts: [LabeledValue]
        public let sources: [CountrySource]
    }

    public static let countryProfiles: [String: CountryProfile] = [
        "France": CountryProfile(
            facts: [
                LabeledValue("Régions et départements", "18 régions · 101 départements"),
                LabeledValue("Communes", "34 875"),
                LabeledValue("Population totale", "68,6 millions"),
                LabeledValue("Climats dominants", "4 — océanique, semi-continental, méditerranéen, montagnard")
            ],
            sources: [
                CountrySource(label: "data.gouv.fr — Référentiel géographique français (communes, départements, régions)", url: "https://www.data.gouv.fr/datasets/referentiel-geographique-francais-communes-unites-urbaines-aires-urbaines-departements-academies-regions-1"),
                CountrySource(label: "data.gouv.fr — Liste des communes de France", url: "https://www.data.gouv.fr/datasets/communes-et-villes-de-france-en-csv-excel-json-parquet-et-feather"),
                CountrySource(label: "data.gouv.fr — Population municipale des communes, France entière", url: "https://www.data.gouv.fr/datasets/population-municipale-des-communes-france-entiere"),
                CountrySource(label: "data.gouv.fr — Données climatologiques de base, mensuelles", url: "https://www.data.gouv.fr/datasets/donnees-climatologiques-de-base-mensuelles")
            ]
        ),
        "Danemark": CountryProfile(
            facts: [
                LabeledValue("Régions et municipalités", "5 régions · 98 municipalités"),
                LabeledValue("Villes et villages", "≈ 1 410 localités (byer)"),
                LabeledValue("Population totale", "6,0 millions"),
                LabeledValue("Climats dominants", "2 — continental humide, océanique tempéré")
            ],
            sources: [
                CountrySource(label: "Statistics Denmark — Municipalities of Denmark", url: "https://en.wikipedia.org/wiki/Municipalities_of_Denmark"),
                CountrySource(label: "Statistics Denmark — Population figures", url: "https://www.dst.dk/en/Statistik/emner/borgere/befolkning"),
                CountrySource(label: "Statistics Denmark — Towns and urban settlements", url: "https://www.dst.dk/en/Statistik/bagtal/2023/2023-06-30-byer"),
                CountrySource(label: "DMI — Danish Meteorological Institute", url: "https://en.wikipedia.org/wiki/Danish_Meteorological_Institute")
            ]
        ),
        "Suède": CountryProfile(
            facts: [
                LabeledValue("Comtés et municipalités", "21 comtés (län) · 290 municipalités"),
                LabeledValue("Villes et villages (tätorter)", "2 017"),
                LabeledValue("Population totale", "10,6 millions"),
                LabeledValue("Climats dominants", "3 — océanique, continental humide, subarctique")
            ],
            sources: [
                CountrySource(label: "SCB — Counties and municipalities", url: "https://www.scb.se/en/finding-statistics/regional-statistics/regional-divisions/counties-and-municipalities/"),
                CountrySource(label: "SCB — Population statistics", url: "https://www.scb.se/en/finding-statistics/statistics-by-subject-area/population-and-living-conditions/population-composition-and-development/population-projections/"),
                CountrySource(label: "Wikipedia — Climate of Sweden", url: "https://en.wikipedia.org/wiki/Climate_of_Sweden")
            ]
        ),
        "Japon": CountryProfile(
            facts: [
                LabeledValue("Préfectures", "47"),
                LabeledValue("Villes, bourgs et villages (municipalités)", "1 719"),
                LabeledValue("Population totale", "123,0 millions"),
                LabeledValue("Climats dominants", "6 — Hokkaidō, mer du Japon, hautes terres centrales, mer intérieure de Seto, façade Pacifique, Ryūkyū")
            ],
            sources: [
                CountrySource(label: "Statistics Bureau of Japan — Statistical Handbook 2025", url: "https://www.stat.go.jp/english/data/handbook/pdf/2025all.pdf"),
                CountrySource(label: "Statistics Bureau of Japan — Population estimates", url: "https://japantoday.com/category/national/update1-japan's-population-marks-sharpest-drop-to-123-mil.-in-2025-census"),
                CountrySource(label: "Wikipedia — Municipalities of Japan", url: "https://en.wikipedia.org/wiki/Municipalities_of_Japan"),
                CountrySource(label: "Wikipedia — Climate of Japan", url: "https://en.wikipedia.org/wiki/Climate_of_Japan")
            ]
        )
    ]
}
