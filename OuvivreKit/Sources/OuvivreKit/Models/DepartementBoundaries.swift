import Foundation
import CoreLocation

/// Simplified département outlines for drawing the selected département's
/// real perimeter on the map (see geo_pipeline), keyed by département name —
/// kommuner danoises comprises (`dk_kommuner_boundaries.json`, même format).
enum DepartementBoundaries {
    private struct Entry: Decodable {
        let nom: String
        let geometry: GeoJSONGeometry
    }

    static let rings: [String: [[CLLocationCoordinate2D]]] = {
        let entries = ["france_departements_boundaries", "dk_kommuner_boundaries"].flatMap { resource -> [Entry] in
            guard let url = Bundle.module.url(forResource: resource, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
            return entries
        }
        return Dictionary(entries.map { ($0.nom, geoJSONOuterRings(of: $0.geometry)) }, uniquingKeysWith: { _, last in last })
    }()

    /// Hit-test manuel : premier département de `names` dont un des anneaux
    /// contient `coordinate` — MapKit ne propose pas de survol/tap par forme
    /// sur `MapPolygon`.
    static func departement(at coordinate: CLLocationCoordinate2D, among names: [String]) -> String? {
        names.first { name in (rings[name] ?? []).contains { ring($0, contains: coordinate) } }
    }

    /// Ray casting standard (pair/impair) sur un anneau de coordonnées.
    private static func ring(_ ring: [CLLocationCoordinate2D], contains coordinate: CLLocationCoordinate2D) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let pi = ring[i], pj = ring[j]
            if (pi.latitude > coordinate.latitude) != (pj.latitude > coordinate.latitude) {
                let slope = (pj.longitude - pi.longitude) / (pj.latitude - pi.latitude)
                let longitudeAtLatitude = pi.longitude + slope * (coordinate.latitude - pi.latitude)
                if coordinate.longitude < longitudeAtLatitude { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
