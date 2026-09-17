import Foundation
import CoreLocation

/// Échantillon de communes françaises réelles (code INSEE, population,
/// densité, coordonnées) catégorisées par taille — sert à démontrer les
/// filtres "Big Mac" (bloc 2) avec un décompte, une liste et des pins carte.
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
    public let coordinate: CLLocationCoordinate2D

    public init(inseeCode: String, name: String, population: Int, densite: Int, lat: Double, lon: Double) {
        self.inseeCode = inseeCode
        self.name = name
        self.population = population
        self.densite = densite
        self.category = CommuneSizeCategory.category(forPopulation: population)
        self.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

public enum CommuneSizeData {
    public static let sample: [CommuneSizeEntry] = [
        // Villages (< 2 000 hab.)
        CommuneSizeEntry(inseeCode: "39300", name: "Ravilloles", population: 480, densite: 27, lat: 46.4167, lon: 5.7833),
        CommuneSizeEntry(inseeCode: "63113", name: "Ceyssat", population: 690, densite: 34, lat: 45.7167, lon: 2.8667),
        CommuneSizeEntry(inseeCode: "24141", name: "Domme", population: 940, densite: 25, lat: 44.8022, lon: 1.2183),
        CommuneSizeEntry(inseeCode: "74010", name: "Argonay", population: 1850, densite: 512, lat: 45.9436, lon: 6.1608),
        CommuneSizeEntry(inseeCode: "89011", name: "Arcy-sur-Cure", population: 480, densite: 15, lat: 47.5972, lon: 3.7469),
        CommuneSizeEntry(inseeCode: "12202", name: "Roquefort-sur-Soulzon", population: 620, densite: 20, lat: 43.9769, lon: 2.9861),
        CommuneSizeEntry(inseeCode: "48095", name: "Le Pont-de-Montvert", population: 260, densite: 5, lat: 44.3908, lon: 3.7492),
        CommuneSizeEntry(inseeCode: "22014", name: "Ploubazlanec", population: 3600, densite: 210, lat: 48.7833, lon: -2.8333),
        CommuneSizeEntry(inseeCode: "04070", name: "Colmars", population: 400, densite: 4, lat: 44.1789, lon: 6.6197),
        CommuneSizeEntry(inseeCode: "2A247", name: "Sant'Antonino", population: 80, densite: 12, lat: 42.5333, lon: 8.9333),
        // Petites villes (2 000 – 20 000 hab.)
        CommuneSizeEntry(inseeCode: "29019", name: "Camaret-sur-Mer", population: 2450, densite: 118, lat: 48.2775, lon: -4.5919),
        CommuneSizeEntry(inseeCode: "07186", name: "Vals-les-Bains", population: 3300, densite: 130, lat: 44.6667, lon: 4.3667),
        CommuneSizeEntry(inseeCode: "46042", name: "Cazals", population: 5200, densite: 92, lat: 44.5667, lon: 1.2667),
        CommuneSizeEntry(inseeCode: "73065", name: "Bourg-Saint-Maurice", population: 7700, densite: 41, lat: 45.6183, lon: 6.7692),
        CommuneSizeEntry(inseeCode: "34120", name: "Pézenas", population: 8300, densite: 305, lat: 43.4614, lon: 3.4239),
        CommuneSizeEntry(inseeCode: "56097", name: "Josselin", population: 2500, densite: 68, lat: 47.9575, lon: -2.5486),
        CommuneSizeEntry(inseeCode: "84007", name: "Bonnieux", population: 1500, densite: 22, lat: 43.8236, lon: 5.3072),
        CommuneSizeEntry(inseeCode: "66136", name: "Prades", population: 6100, densite: 180, lat: 42.6167, lon: 2.4167),
        CommuneSizeEntry(inseeCode: "17021", name: "Ars-en-Ré", population: 1300, densite: 145, lat: 46.2039, lon: -1.5197),
        CommuneSizeEntry(inseeCode: "21231", name: "Flavigny-sur-Ozerain", population: 300, densite: 40, lat: 47.4867, lon: 4.5350),
        CommuneSizeEntry(inseeCode: "01053", name: "Bourg-en-Bresse", population: 41_400, densite: 2200, lat: 46.2044, lon: 5.2260),
        CommuneSizeEntry(inseeCode: "50536", name: "Saint-Lô", population: 18_800, densite: 480, lat: 49.1147, lon: -1.0906),
        CommuneSizeEntry(inseeCode: "40192", name: "Mont-de-Marsan", population: 30_200, densite: 620, lat: 43.8905, lon: -0.4986),
        // Villes moyennes (20 000 – 100 000 hab.)
        CommuneSizeEntry(inseeCode: "24322", name: "Périgueux", population: 29_500, densite: 2400, lat: 45.1848, lon: 0.7218),
        CommuneSizeEntry(inseeCode: "65440", name: "Tarbes", population: 40_800, densite: 2650, lat: 43.2333, lon: 0.0833),
        CommuneSizeEntry(inseeCode: "17300", name: "Rochefort", population: 24_100, densite: 1450, lat: 45.9422, lon: -0.9581),
        CommuneSizeEntry(inseeCode: "89024", name: "Auxerre", population: 34_600, densite: 1100, lat: 47.7975, lon: 3.5731),
        CommuneSizeEntry(inseeCode: "03185", name: "Moulins", population: 19_800, densite: 780, lat: 46.5653, lon: 3.3325),
        CommuneSizeEntry(inseeCode: "48189", name: "Mende", population: 12_000, densite: 210, lat: 44.5183, lon: 3.5008),
        CommuneSizeEntry(inseeCode: "68224", name: "Saint-Louis", population: 22_500, densite: 1900, lat: 47.5883, lon: 7.5622),
        CommuneSizeEntry(inseeCode: "22278", name: "Saint-Brieuc", population: 44_300, densite: 2600, lat: 48.5136, lon: -2.7653),
        CommuneSizeEntry(inseeCode: "10387", name: "Troyes", population: 61_000, densite: 4200, lat: 48.2973, lon: 4.0744),
        CommuneSizeEntry(inseeCode: "57463", name: "Sarreguemines", population: 21_500, densite: 1350, lat: 49.1094, lon: 7.0672),
        CommuneSizeEntry(inseeCode: "62193", name: "Calais", population: 72_500, densite: 3050, lat: 50.9513, lon: 1.8587),
        // Grandes villes (> 100 000 hab.)
        CommuneSizeEntry(inseeCode: "69123", name: "Lyon", population: 522_000, densite: 10_700, lat: 45.7640, lon: 4.8357),
        CommuneSizeEntry(inseeCode: "13055", name: "Marseille", population: 873_000, densite: 3620, lat: 43.2965, lon: 5.3698),
        CommuneSizeEntry(inseeCode: "31555", name: "Toulouse", population: 493_000, densite: 4200, lat: 43.6047, lon: 1.4442),
        CommuneSizeEntry(inseeCode: "44109", name: "Nantes", population: 320_000, densite: 4900, lat: 47.2184, lon: -1.5536),
        CommuneSizeEntry(inseeCode: "33063", name: "Bordeaux", population: 260_000, densite: 5600, lat: 44.8378, lon: -0.5792),
        CommuneSizeEntry(inseeCode: "59350", name: "Lille", population: 233_000, densite: 6900, lat: 50.6292, lon: 3.0573),
        CommuneSizeEntry(inseeCode: "67482", name: "Strasbourg", population: 291_000, densite: 3600, lat: 48.5734, lon: 7.7521),
        CommuneSizeEntry(inseeCode: "35238", name: "Rennes", population: 220_000, densite: 4600, lat: 48.1173, lon: -1.6778),
        CommuneSizeEntry(inseeCode: "06088", name: "Nice", population: 342_000, densite: 4900, lat: 43.7102, lon: 7.2620),
        CommuneSizeEntry(inseeCode: "34172", name: "Montpellier", population: 295_000, densite: 5500, lat: 43.6108, lon: 3.8767),
        CommuneSizeEntry(inseeCode: "76540", name: "Rouen", population: 114_000, densite: 7100, lat: 49.4431, lon: 1.0993),
        CommuneSizeEntry(inseeCode: "51454", name: "Reims", population: 182_000, densite: 3900, lat: 49.2583, lon: 4.0317),
        CommuneSizeEntry(inseeCode: "42218", name: "Saint-Étienne", population: 172_000, densite: 3000, lat: 45.4397, lon: 4.3872),
        CommuneSizeEntry(inseeCode: "83137", name: "Toulon", population: 176_000, densite: 4300, lat: 43.1242, lon: 5.9280)
    ]

    /// Nombre de communes de l'échantillon correspondant aux catégories
    /// actuellement cochées — c'est le seul effet observable des 4 nouvelles
    /// bascules tant qu'aucune couche carte par commune n'existe.
    public static func count(includeVillage: Bool, includePetiteVille: Bool, includeVilleMoyenne: Bool, includeGrandeVille: Bool) -> Int {
        matching(includeVillage: includeVillage, includePetiteVille: includePetiteVille, includeVilleMoyenne: includeVilleMoyenne, includeGrandeVille: includeGrandeVille).count
    }

    /// Communes de l'échantillon correspondant aux catégories actuellement
    /// cochées, triées par population décroissante — sert à alimenter la
    /// liste et les pins carte du bloc "Régions".
    public static func matching(includeVillage: Bool, includePetiteVille: Bool, includeVilleMoyenne: Bool, includeGrandeVille: Bool) -> [CommuneSizeEntry] {
        sample.filter { entry in
            switch entry.category {
            case .village: return includeVillage
            case .petiteVille: return includePetiteVille
            case .villeMoyenne: return includeVilleMoyenne
            case .grandeVille: return includeGrandeVille
            }
        }.sorted { $0.population > $1.population }
    }
}
