import Foundation

/// ~34 900 communes françaises réelles (code INSEE, population, densité,
/// département) catégorisées par taille — alimente les filtres "Big Mac"
/// (bloc Régions) avec un décompte et la liste de départements correspondants.
///
/// Source : Liste des communes de France (code INSEE, codes postaux, EPCI,
/// population, superficie, 62 indicateurs) —
/// https://www.data.gouv.fr/datasets/liste-des-communes-de-france-code-insee-codes-postaux-epci-population-superficie-62-indicateurs
/// Généré offline par `geo_pipeline/build_communes_data.py` — voir
/// `geo_pipeline/README.md`.
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

public struct CommuneSizeEntry: Identifiable, Decodable {
    public var id: String { inseeCode }
    public let inseeCode: String
    public let name: String
    public let departementCode: String
    public let population: Int
    /// Habitants au km².
    public let densite: Int
    public let category: CommuneSizeCategory

    enum CodingKeys: String, CodingKey {
        case inseeCode = "insee"
        case name
        case departementCode
        case population
        case densite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inseeCode = try c.decode(String.self, forKey: .inseeCode)
        name = try c.decode(String.self, forKey: .name)
        departementCode = try c.decode(String.self, forKey: .departementCode)
        population = try c.decode(Int.self, forKey: .population)
        densite = try c.decode(Int.self, forKey: .densite)
        category = CommuneSizeCategory.category(forPopulation: population)
    }

    public init(inseeCode: String, name: String, departementCode: String, population: Int, densite: Int) {
        self.inseeCode = inseeCode
        self.name = name
        self.departementCode = departementCode
        self.population = population
        self.densite = densite
        self.category = CommuneSizeCategory.category(forPopulation: population)
    }
}

public enum CommuneSizeData {
    private struct Root: Decodable {
        let communes: [CommuneSizeEntry]
    }

    /// ~34 900 communes réelles, chargées une seule fois depuis
    /// `communes_data.json` (généré offline — voir `geo_pipeline/README.md`),
    /// exactement comme `FranceGeoData.departements`.
    public static let sample: [CommuneSizeEntry] = {
        guard let url = Bundle.module.url(forResource: "communes_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else {
            return []
        }
        return root.communes
    }()

    /// Communes par catégorie, précalculées une fois — évite de refiltrer
    /// ~35k entrées sur chaque changement d'état (glissement de curseur,
    /// bascule d'une autre case), puisque seules les 4 cases à cocher
    /// changent le sous-ensemble à afficher, pas les communes elles-mêmes.
    private static let byCategory: [CommuneSizeCategory: [CommuneSizeEntry]] = {
        Dictionary(grouping: sample, by: \.category)
    }()

    /// Nombre de communes correspondant aux catégories actuellement cochées —
    /// somme des tailles des groupes précalculés, sans filtrer/trier ~35k
    /// entrées (contrairement à `matching`, plus coûteux et réservé à
    /// l'affichage d'une liste).
    public static func count(includeVillage: Bool, includePetiteVille: Bool, includeVilleMoyenne: Bool, includeGrandeVille: Bool) -> Int {
        var total = 0
        if includeVillage { total += byCategory[.village]?.count ?? 0 }
        if includePetiteVille { total += byCategory[.petiteVille]?.count ?? 0 }
        if includeVilleMoyenne { total += byCategory[.villeMoyenne]?.count ?? 0 }
        if includeGrandeVille { total += byCategory[.grandeVille]?.count ?? 0 }
        return total
    }

    /// Communes correspondant aux catégories actuellement cochées, triées
    /// par population décroissante — sert à alimenter le décompte et les
    /// départements correspondants du bloc "Régions".
    public static func matching(includeVillage: Bool, includePetiteVille: Bool, includeVilleMoyenne: Bool, includeGrandeVille: Bool) -> [CommuneSizeEntry] {
        var result: [CommuneSizeEntry] = []
        if includeVillage { result += byCategory[.village] ?? [] }
        if includePetiteVille { result += byCategory[.petiteVille] ?? [] }
        if includeVilleMoyenne { result += byCategory[.villeMoyenne] ?? [] }
        if includeGrandeVille { result += byCategory[.grandeVille] ?? [] }
        return result.sorted { $0.population > $1.population }
    }

    /// Codes département distincts correspondant aux catégories cochées —
    /// évite de faire porter à `BigMacView` un `.map` + `Set` sur ~35k
    /// entrées triées à chaque re-render (voir `matchingDepartementCodes`).
    public static func matchingDepartementCodes(includeVillage: Bool, includePetiteVille: Bool, includeVilleMoyenne: Bool, includeGrandeVille: Bool) -> Set<String> {
        var codes = Set<String>()
        if includeVillage { codes.formUnion((byCategory[.village] ?? []).map(\.departementCode)) }
        if includePetiteVille { codes.formUnion((byCategory[.petiteVille] ?? []).map(\.departementCode)) }
        if includeVilleMoyenne { codes.formUnion((byCategory[.villeMoyenne] ?? []).map(\.departementCode)) }
        if includeGrandeVille { codes.formUnion((byCategory[.grandeVille] ?? []).map(\.departementCode)) }
        return codes
    }
}
