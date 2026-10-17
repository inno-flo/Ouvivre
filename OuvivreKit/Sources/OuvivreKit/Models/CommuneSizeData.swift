import Foundation

/// ~34 900 communes françaises réelles (code INSEE, population, densité,
/// département) catégorisées par taille — alimente les filtres "Big Mac"
/// (bloc Régions) avec la liste de départements correspondants.
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
enum CommuneSizeCategory: String, CaseIterable, Identifiable {
    case village = "Village"
    case petiteVille = "Petite ville"
    case villeMoyenne = "Ville moyenne"
    case grandeVille = "Grande ville"
    var id: Self { self }

    var description: String {
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

    static func category(forPopulation population: Int) -> CommuneSizeCategory {
        switch population {
        case ..<2_000: return .village
        case 2_000..<20_000: return .petiteVille
        case 20_000..<100_000: return .villeMoyenne
        default: return .grandeVille
        }
    }
}

enum CommuneSizeData {
    /// Seuls le département et la population de chaque commune servent :
    /// les autres champs du JSON sont ignorés au décodage.
    private struct Commune: Decodable {
        let departementCode: String
        let population: Int
    }

    private struct Root: Decodable {
        let generatedAt: String
        let communes: [Commune]
    }

    /// Byer danoises (`dk_byer_data.json`, DST BY3), rattachées à leur
    /// kommune — même catégorisation par population que les communes.
    private struct By: Decodable {
        let kommuneCode: String
        let population: Int
    }

    private struct DenmarkRoot: Decodable {
        let byer: [By]
    }

    /// Codes département par catégorie, précalculés une fois depuis les
    /// ~34 900 communes réelles de `communes_data.json` (généré offline —
    /// voir `geo_pipeline/README.md`) — évite de refiltrer ~35k entrées sur
    /// chaque changement d'état (glissement de curseur, bascule d'une autre
    /// case), puisque seules les 4 cases à cocher changent le sous-ensemble.
    /// Les communes elles-mêmes ne sont pas gardées en mémoire.
    private static let loaded: (generatedAt: String?, codesByCategory: [CommuneSizeCategory: Set<String>]) = {
        guard let url = Bundle.module.url(forResource: "communes_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else { return (nil, [:]) }
        var codes: [CommuneSizeCategory: Set<String>] = [:]
        for commune in root.communes {
            codes[.category(forPopulation: commune.population), default: []].insert(commune.departementCode)
        }
        // Les kommuner s'ajoutent aux mêmes ensembles : leurs codes ne
        // recoupent aucun code département.
        if let url = Bundle.module.url(forResource: "dk_byer_data", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let denmark = try? JSONDecoder().decode(DenmarkRoot.self, from: data) {
            for by in denmark.byer {
                codes[.category(forPopulation: by.population), default: []].insert(by.kommuneCode)
            }
        }
        return (root.generatedAt, codes)
    }()

    static var generatedAt: String? { loaded.generatedAt }

    /// Codes département distincts correspondant aux catégories cochées.
    static func matchingDepartementCodes(_ categories: Set<CommuneSizeCategory>) -> Set<String> {
        categories.reduce(into: Set<String>()) { $0.formUnion(loaded.codesByCategory[$1] ?? []) }
    }
}
