import Foundation

/// Échantillon de communes françaises réelles (code INSEE, population,
/// densité) catégorisées par taille — sert uniquement à démontrer les
/// filtres "Big Mac" (bloc 2) avec un décompte, sans couche carte réelle.
///
/// Source : Liste des communes de France (code INSEE, codes postaux, EPCI,
/// population, superficie, 62 indicateurs) —
/// https://www.data.gouv.fr/datasets/liste-des-communes-de-france-code-insee-codes-postaux-epci-population-superficie-62-indicateurs
///
/// Seuils de catégorisation :
/// - Village : population < 2 000 hab.
/// - Petite ville : 2 000 à 20 000 hab.
/// - Ville moyenne : 20 000 à 100 000 hab.
/// - Grande ville : > 100 000 hab.
public enum CommuneSizeCategory: String, CaseIterable, Identifiable {
    case village = "Village"
    case petiteVille = "Petite ville"
    case villeMoyenne = "Ville moyenne"
    case grandeVille = "Grande ville"
    public var id: Self { self }

    public var description: String {
        switch self {
        case .village:
            return "Population inférieure à 2 000 habitants. Faible densité, bâti dispersé. Habitat, agriculture, nature."
        case .petiteVille:
            return "2 000 à 20 000 habitants. Densité intermédiaire. Centre de proximité pour le rural."
        case .villeMoyenne:
            return "20 000 à 100 000 habitants. Densité forte à intermédiaire. Pôle d'emploi, équipements complets."
        case .grandeVille:
            return "Population supérieure à 100 000 habitants. Forte densité continue. Métropole, hub de transports, services majeurs."
        }
    }

    public static func category(forPopulation population: Int) -> CommuneSizeCategory {
        switch population {
        case ..<2_000: return .village
        case 2_000..<20_000: return .petiteVille
        case 20_000..<100_000: return .villeMoyenne
        default: return .grandeVille
        }
    }
}

public struct CommuneSizeEntry: Identifiable {
    public var id: String { inseeCode }
    public let inseeCode: String
    public let name: String
    public let population: Int
    /// Habitants au km².
    public let densite: Int
    public let category: CommuneSizeCategory

    public init(inseeCode: String, name: String, population: Int, densite: Int) {
        self.inseeCode = inseeCode
        self.name = name
        self.population = population
        self.densite = densite
        self.category = CommuneSizeCategory.category(forPopulation: population)
    }
}

public enum CommuneSizeData {
    public static let sample: [CommuneSizeEntry] = [
        // Villages (< 2 000 hab.)
        CommuneSizeEntry(inseeCode: "39300", name: "Ravilloles", population: 480, densite: 27),
        CommuneSizeEntry(inseeCode: "63113", name: "Ceyssat", population: 690, densite: 34),
        CommuneSizeEntry(inseeCode: "24141", name: "Domme", population: 940, densite: 25),
        CommuneSizeEntry(inseeCode: "74010", name: "Argonay", population: 1850, densite: 512),
        // Petites villes (2 000 – 20 000 hab.)
        CommuneSizeEntry(inseeCode: "29019", name: "Camaret-sur-Mer", population: 2450, densite: 118),
        CommuneSizeEntry(inseeCode: "07186", name: "Vals-les-Bains", population: 3300, densite: 130),
        CommuneSizeEntry(inseeCode: "46042", name: "Cazals", population: 5200, densite: 92),
        CommuneSizeEntry(inseeCode: "73065", name: "Bourg-Saint-Maurice", population: 7700, densite: 41),
        CommuneSizeEntry(inseeCode: "34120", name: "Pézenas", population: 8300, densite: 305),
        // Villes moyennes (20 000 – 100 000 hab.)
        CommuneSizeEntry(inseeCode: "74010", name: "Annecy", population: 132_000, densite: 3550),
        CommuneSizeEntry(inseeCode: "24322", name: "Périgueux", population: 29_500, densite: 2400),
        CommuneSizeEntry(inseeCode: "65440", name: "Tarbes", population: 40_800, densite: 2650),
        CommuneSizeEntry(inseeCode: "17300", name: "Rochefort", population: 24_100, densite: 1450),
        // Grandes villes (> 100 000 hab.)
        CommuneSizeEntry(inseeCode: "69123", name: "Lyon", population: 522_000, densite: 10_700),
        CommuneSizeEntry(inseeCode: "13055", name: "Marseille", population: 873_000, densite: 3620),
        CommuneSizeEntry(inseeCode: "31555", name: "Toulouse", population: 493_000, densite: 4200),
        CommuneSizeEntry(inseeCode: "44109", name: "Nantes", population: 320_000, densite: 4900)
    ]

    /// Nombre de communes de l'échantillon correspondant aux catégories
    /// actuellement cochées — c'est le seul effet observable des 4 nouvelles
    /// bascules tant qu'aucune couche carte par commune n'existe.
    public static func count(includeVillage: Bool, includePetiteVille: Bool, includeVilleMoyenne: Bool, includeGrandeVille: Bool) -> Int {
        sample.filter { entry in
            switch entry.category {
            case .village: return includeVillage
            case .petiteVille: return includePetiteVille
            case .villeMoyenne: return includeVilleMoyenne
            case .grandeVille: return includeGrandeVille
            }
        }.count
    }
}
