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
    public static let meteo: [(String, Int)] = [
        ("Températures", 4), ("Température ressentie", 3), ("Ensoleillement", 4),
        ("Durée d'ensoleillement", 3), ("Précipitations", 2), ("Vent", 2),
        ("Nuages", 2), ("Qualité de l'air", 5), ("Humidité", 3)
    ]
    public struct Group {
        public let title: String
        public let rows: [(String, Int)]
    }
    public static let groups: [Group] = [
        Group(title: "CULTURE", rows: [("Musées", 4), ("Équipements culturels", 3), ("Lieux du patrimoine", 4), ("Centre ancien", 5), ("Événements annuels", 3), ("Festivals", 3), ("Salons", 1)]),
        Group(title: "TAILLE", rows: [("Superficie de la ville", 2), ("Nombre d'habitants", 3)]),
        Group(title: "MOBILITÉ", rows: [("Bus", 3), ("Pistes cyclables", 5), ("Gares", 4), ("Aéroports", 2)]),
        Group(title: "QUALITÉ DE VIE", rows: [("Classements de livabilité", 4)])
    ]

    public struct CityBar { public let key: String; public let value: Int }
    public struct City {
        public let name: String
        public let sub: String
        public let score: Int
        public let bars: [CityBar]
        public let inline: String
    }
    public static let cities: [City] = [
        City(name: "Annecy", sub: "Haute-Savoie · 132 000 hab.", score: 94,
             bars: [.init(key: "Géo", value: 98), .init(key: "Météo", value: 88), .init(key: "Culture", value: 91)],
             inline: "Lac 0,4 km · Montagne 6 km · Gare TGV"),
        City(name: "Chambéry", sub: "Savoie · 60 100 hab.", score: 89,
             bars: [.init(key: "Géo", value: 92), .init(key: "Météo", value: 86), .init(key: "Culture", value: 88)],
             inline: "Lac 12 km · Montagne 4 km · Gare TGV"),
        City(name: "Aix-les-Bains", sub: "Savoie · 31 200 hab.", score: 86,
             bars: [.init(key: "Géo", value: 95), .init(key: "Météo", value: 84), .init(key: "Culture", value: 76)],
             inline: "Lac 0,8 km · Montagne 5 km · Gare"),
        City(name: "Thonon-les-Bains", sub: "Haute-Savoie · 35 900 hab.", score: 82,
             bars: [.init(key: "Géo", value: 93), .init(key: "Météo", value: 79), .init(key: "Culture", value: 71)],
             inline: "Lac 0,5 km · Montagne 9 km · Gare"),
        City(name: "Albertville", sub: "Savoie · 19 400 hab.", score: 74,
             bars: [.init(key: "Géo", value: 88), .init(key: "Météo", value: 72), .init(key: "Culture", value: 61)],
             inline: "Lac 28 km · Montagne 2 km · Gare")
    ]

    public static let countries = ["France", "Danemark", "Suède", "Japon"]
    public static let tags = ["indifférent", "accessoire", "souhaitable", "important", "prioritaire", "déterminant"]
    /// Géographie 2's 3-level scale (0...2) — "accessoire", "souhaitable" et "prioritaire" fusionnés dans "important".
    public static let tagsGeo2 = ["indifférent", "important", "déterminant"]

    public static let indexStats = [LabeledValue("RÉGIONS INDEXÉES", "18"), LabeledValue("VILLES > 15 000 HAB.", "1 214"), LabeledValue("SOURCES OUVERTES", "11")]

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

    public static let rankings = [
        LabeledValue("Baromètre des villes cyclables", "Annecy — A"),
        LabeledValue("Palmarès qualité de vie 2025", "Annecy — 3e"),
        LabeledValue("Indice air ATMO", "Chambéry — 41"),
        LabeledValue("Villes où il fait bon vivre", "Aix-les-Bains — 21e")
    ]

    public struct VilleFamily { public let key: String; public let value: Int; public let note: String }
    public struct VilleMonth { public let label: String; public let temp: Int }
    public static let ville = (
        name: "Annecy", dept: "HAUTE-SAVOIE · AUVERGNE-RHÔNE-ALPES", score: 94,
        blurb: "Ville lacustre adossée au massif des Bornes, centre médiéval sur canaux, desserte TGV directe et 68 km de pistes cyclables continues. Correspond à vos pondérations fortes sur lacs, montagne et centre ancien.",
        stats: [
            LabeledValue("HABITANTS", "132 000"), LabeledValue("SUPERFICIE", "13,6 km²"),
            LabeledValue("ALTITUDE", "448 m"), LabeledValue("ENSOLEILLEMENT", "1 924 h/an"),
            LabeledValue("PRÉCIPITATIONS", "1 220 mm"), LabeledValue("QUALITÉ DE L'AIR", "Bonne — 32")
        ],
        families: [
            VilleFamily(key: "Géographie", value: 98, note: "lac + montagne"),
            VilleFamily(key: "Météo", value: 88, note: "air très bon"),
            VilleFamily(key: "Culture", value: 91, note: "7 musées · 14 festivals"),
            VilleFamily(key: "Taille", value: 79, note: "moyenne, dense"),
            VilleFamily(key: "Mobilité", value: 86, note: "TGV · vélo A"),
            VilleFamily(key: "Livabilité", value: 93, note: "3e au national")
        ],
        temps: [2, 3, 7, 11, 15, 19, 21, 20, 16, 12, 6, 3],
        distances: [
            LabeledValue("Lac d'Annecy", "0,4 km"), LabeledValue("Premier sommet > 1 500 m", "6 km"),
            LabeledValue("Forêt publique", "2,1 km"), LabeledValue("Mer", "310 km"),
            LabeledValue("Gare TGV", "en ville"), LabeledValue("Aéroport (Genève)", "45 min")
        ],
        warnings: [
            "Tension immobilière élevée : +62 % au m² en dix ans.",
            "Trafic estival saturé sur les rives du lac.",
            "Précipitations annuelles supérieures à votre seuil de tolérance."
        ]
    )
}
