import Foundation
import CoreLocation

/// Commune française retrouvée à partir d'une étiquette de localité de la
/// carte (population, catégorie de taille).
struct CommuneInfo {
    let name: String
    let departementCode: String
    let population: Int
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
                population: commune.population,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }()

    /// Décode le fichier en tâche de fond, pour que le premier clic ne paie pas
    /// le décodage (plusieurs centaines de ms en Debug).
    static func preload() { _ = all.count }

    /// Communes dont le centre tombe dans le rectangle donné (en degrés).
    static func communes(latitudes: ClosedRange<Double>, longitudes: ClosedRange<Double>) -> [CommuneInfo] {
        all.filter { latitudes.contains($0.coordinate.latitude) && longitudes.contains($0.coordinate.longitude) }
    }

    /// Commune « sous le clic » : parmi celles dont le centre tombe dans l'ellipse
    /// de demi-axes `halfWidth` × `halfHeight` (en degrés) autour de `coordinate`
    /// — large et basse, pour couvrir le nom écrit autour de son point —, celle
    /// de meilleur score population^0,3 / (distance² + ε), distance normalisée
    /// par l'ellipse. La proximité domine (cliquer sur une localité voisine d'une
    /// grande ville donne la voisine), la population départage seulement les
    /// centres proches. Pas de seuil : une ellipse non vide donne toujours une réponse.
    static func commune(near coordinate: CLLocationCoordinate2D, halfWidth: Double, halfHeight: Double) -> CommuneInfo? {
        guard halfWidth > 0, halfHeight > 0 else { return nil }
        var best: CommuneInfo?
        var bestScore = 0.0
        for commune in all {
            let dx = (commune.coordinate.longitude - coordinate.longitude) / halfWidth
            let dy = (commune.coordinate.latitude - coordinate.latitude) / halfHeight
            let d2 = dx * dx + dy * dy
            guard d2 <= 1 else { continue }
            let score = pow(Double(max(commune.population, 1)), 0.3) / (d2 + 0.03)
            if score > bestScore { best = commune; bestScore = score }
        }
        return best
    }
}
