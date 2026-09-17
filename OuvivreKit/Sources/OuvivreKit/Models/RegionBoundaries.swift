import Foundation
import CoreLocation

/// Simplified région outlines (outer ring only, small islands dropped) for
/// drawing the selected région's real perimeter on the map — see
/// geo_pipeline/build_region_boundaries.py-equivalent step (IGN BD TOPO,
/// simplified with shapely, ~98 KB for all 18 régions incl. outre-mer).
public enum RegionBoundaries {
    private struct Entry: Decodable {
        let nom: String
        let geometry: GeoJSONGeometry
    }

    /// One coordinate ring per element; a région with several landmasses
    /// (e.g. Guadeloupe) has more than one.
    public static let rings: [String: [[CLLocationCoordinate2D]]] = {
        guard let url = Bundle.module.url(forResource: "france_regions_boundaries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return [:]
        }
        var result: [String: [[CLLocationCoordinate2D]]] = [:]
        for entry in entries {
            result[entry.nom] = geoJSONOuterRings(of: entry.geometry)
        }
        return result
    }()
}
