import Foundation
import CoreLocation

/// Commune française retrouvée à partir d'une étiquette de localité de la
/// carte (population, densité, catégorie de taille).
struct CommuneInfo {
    let name: String
    let departementCode: String
    let population: Int
    let densite: Int?
    let coordinate: CLLocationCoordinate2D

    var category: CommuneSizeCategory { .category(forPopulation: population) }
}

/// Rapprochement d'une étiquette de localité de la carte (nom + coordonnées
/// fournis par MapKit) avec les ~34 900 communes de `communes_data.json`.
/// Le fichier est décodé à la première demande (pas au lancement) et gardé en
/// mémoire, indexé par nom normalisé : un clic ne parcourt que les communes
/// homonymes.
enum CommuneLookup {
    private struct Commune: Decodable {
        let name: String
        let departementCode: String
        let population: Int
        let densite: Int?
        let lat: Double?
        let lon: Double?
    }

    private struct Root: Decodable {
        let communes: [Commune]
    }

    /// Distance maximale entre l'étiquette cliquée et le centre de la commune
    /// de même nom : les centroïdes INSEE s'écartent de l'étiquette Apple (qui
    /// vise le centre-ville) de quelques kilomètres, plus pour les grandes communes.
    private static let maxDistance: CLLocationDistance = 25_000

    private static let byNormalizedName: [String: [CommuneInfo]] = {
        guard let url = Bundle.module.url(forResource: "communes_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else { return [:] }
        var index: [String: [CommuneInfo]] = [:]
        for commune in root.communes {
            guard let lat = commune.lat, let lon = commune.lon else { continue }
            let info = CommuneInfo(
                name: commune.name, departementCode: commune.departementCode,
                population: commune.population, densite: commune.densite,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            index[normalize(commune.name), default: []].append(info)
        }
        return index
    }()

    /// Commune de même nom que `title`, la plus proche de `coordinate`, à
    /// moins de `maxDistance` — `nil` si l'étiquette n'est pas une commune
    /// (région, hameau, lieu-dit…) ou si le doute est trop grand.
    static func commune(named title: String, near coordinate: CLLocationCoordinate2D) -> CommuneInfo? {
        guard let candidates = byNormalizedName[normalize(title)] else { return nil }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return candidates
            .map { ($0, origin.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))) }
            .filter { $0.1 <= maxDistance }
            .min { $0.1 < $1.1 }?.0
    }

    /// Minuscules sans accents ni ponctuation, « Saint(e) » abrégé : « Saint-Étienne »
    /// et « St Etienne » donnent la même clé.
    private static func normalize(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { word -> Substring in
            switch word {
            case "saint": return "st"
            case "sainte": return "ste"
            default: return word
            }
        }
        return words.joined(separator: " ")
    }
}
