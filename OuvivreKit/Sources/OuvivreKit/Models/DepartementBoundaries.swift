import Foundation
import CoreLocation

/// Simplified département outlines + a camera place (centroid + a span
/// sized to its bounding box) for drawing the selected département's real
/// perimeter on the map. Départements have no hand-authored GeoCoordinates
/// entry, so the place is computed geometrically (see geo_pipeline) instead.
public enum DepartementBoundaries {
    public struct Place {
        public let coordinate: CLLocationCoordinate2D
        public let span: Double
    }

    private struct Entry: Decodable {
        let nom: String
        let lat: Double
        let lon: Double
        let span: Double
        let geometry: GeoJSONGeometry
    }

    public static let rings: [String: [[CLLocationCoordinate2D]]] = entriesByName.mapValues { $0.rings }
    public static let places: [String: Place] = entriesByName.mapValues { $0.place }

    private static let entriesByName: [String: (rings: [[CLLocationCoordinate2D]], place: Place)] = {
        guard let url = Bundle.module.url(forResource: "france_departements_boundaries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return [:]
        }
        var result: [String: (rings: [[CLLocationCoordinate2D]], place: Place)] = [:]
        for entry in entries {
            let place = Place(coordinate: CLLocationCoordinate2D(latitude: entry.lat, longitude: entry.lon), span: entry.span)
            result[entry.nom] = (geoJSONOuterRings(of: entry.geometry), place)
        }
        return result
    }()
}
