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
        ("Proximité d'un pays étranger", 2),
        ("Proximité de la mer", 1),
        ("Proximité de la montagne", 5),
        ("Proximité de lacs", 5),
        ("Proximité de fleuves et rivières", 3),
        ("Proximité de parcs et forêts publiques", 4)
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

    public static let regions: [(String, Int)] = [
        ("Isère", 89), ("Pyrénées-Atlantiques", 85), ("Hautes-Alpes", 82),
        ("Hautes-Pyrénées", 78), ("Puy-de-Dôme", 74), ("Doubs", 71)
    ]
    public static let countries = ["France", "Danemark", "Suède", "Japon"]
    public static let tags = ["indifférent", "accessoire", "souhaitable", "important", "prioritaire", "déterminant"]

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
                LabeledValue("Villes et villages (communes)", "34 875"),
                LabeledValue("Population totale", "68,6 M"),
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
                LabeledValue("Population totale", "6,0 M"),
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
                LabeledValue("Population totale", "10,6 M"),
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
                LabeledValue("Population totale", "123,0 M"),
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

    /// [label, values for the 3 compared cities, index of the best cell]
    public static let compareData: [(String, [String], Int)] = [
        ("Habitants", ["132 000", "60 100", "31 200"], 0),
        ("Superficie", ["13,6 km²", "21,0 km²", "18,9 km²"], 1),
        ("Altitude", ["448 m", "270 m", "265 m"], 0),
        ("Distance montagne", ["6 km", "4 km", "5 km"], 1),
        ("Distance lac", ["0,4 km", "12 km", "0,8 km"], 0),
        ("Ensoleillement", ["1 924 h/an", "1 987 h/an", "1 951 h/an"], 1),
        ("Précipitations", ["1 220 mm", "1 140 mm", "1 180 mm"], 1),
        ("Qualité de l'air", ["Bonne (32)", "Moyenne (41)", "Bonne (34)"], 0),
        ("Musées", ["7", "9", "4"], 1),
        ("Centre ancien", ["Oui — médiéval", "Oui — carré Curial", "Partiel"], 0),
        ("Festivals / an", ["14", "11", "8"], 0),
        ("Pistes cyclables", ["68 km", "42 km", "39 km"], 0),
        ("Gares", ["TGV directe", "TGV directe", "TER"], 0),
        ("Aéroport < 1 h", ["Genève", "Lyon-St-Exupéry", "Genève"], 0),
        ("Livabilité (Fr.)", ["3e / 100", "12e / 100", "21e / 100"], 0)
    ]

    public struct SavedSearch { public let title: String; public let meta: String; public let tags: [String]; public let score: Int }
    public static let saved = [
        SavedSearch(title: "Alpes du Nord — lacs & montagne", meta: "Créée le 14 mars · 20 critères · 5 villes", tags: ["Montagne 5/5", "Lacs 5/5", "Vélo 5/5", "Mer 1/5"], score: 94),
        SavedSearch(title: "Sud-Ouest — océan & patrimoine", meta: "Créée le 2 mars · 18 critères · 5 villes", tags: ["Mer 5/5", "Patrimoine 4/5", "Ensoleillement 5/5"], score: 88),
        SavedSearch(title: "Massif central — calme & forêts", meta: "Créée le 21 février · 15 critères · 4 villes", tags: ["Forêts 5/5", "Habitants 2/5", "Air 5/5"], score: 81)
    ]
}
