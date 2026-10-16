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

/// Recherche de la commune sous un clic sur la carte, parmi les ~34 900
/// communes de `communes_data.json`. Le fichier est décodé à la première
/// demande (pas au lancement) et gardé en mémoire.
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

    private static let all: [CommuneInfo] = {
        guard let url = Bundle.module.url(forResource: "communes_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else { return [] }
        return root.communes.compactMap { commune in
            guard let lat = commune.lat, let lon = commune.lon else { return nil }
            return CommuneInfo(
                name: commune.name, departementCode: commune.departementCode,
                population: commune.population, densite: commune.densite,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }()

    /// Commune la plus peuplée dont le centre tombe dans l'ellipse de demi-axes
    /// `halfWidth` × `halfHeight` (en degrés) autour de `coordinate`. L'ellipse,
    /// large et basse, couvre le nom de la localité écrit autour de son point.
    /// Plus la carte est dézoomée, plus le seuil de population monte : on ne
    /// retient que les communes dont Apple Plans affiche vraisemblablement le nom.
    static func commune(near coordinate: CLLocationCoordinate2D, halfWidth: Double, halfHeight: Double) -> CommuneInfo? {
        guard halfWidth > 0, halfHeight > 0 else { return nil }
        let minimumPopulation: Int
        switch halfWidth {
        case 0.3...: minimumPopulation = 50_000
        case 0.12...: minimumPopulation = 10_000
        case 0.04...: minimumPopulation = 2_000
        default: minimumPopulation = 0
        }
        var best: CommuneInfo?
        for commune in all where commune.population >= minimumPopulation && commune.population > (best?.population ?? -1) {
            let dx = (commune.coordinate.longitude - coordinate.longitude) / halfWidth
            let dy = (commune.coordinate.latitude - coordinate.latitude) / halfHeight
            if dx * dx + dy * dy <= 1 { best = commune }
        }
        return best
    }
}
