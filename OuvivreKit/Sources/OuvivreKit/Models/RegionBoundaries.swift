import Foundation
import CoreLocation

/// Simplified région outlines (outer ring only, small islands dropped) for
/// drawing the selected région's real perimeter on the map — see
/// geo_pipeline/build_region_boundaries.py-equivalent step (IGN BD TOPO,
/// simplified with shapely, ~98 KB for all 18 régions incl. outre-mer).
public enum RegionBoundaries {
    private struct Geometry: Decodable {
        let type: String
        let coordinates: JSONValue
    }
    private struct Entry: Decodable {
        let nom: String
        let geometry: Geometry
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
            result[entry.nom] = outerRings(of: entry.geometry)
        }
        return result
    }()

    /// A Polygon's coordinates are `[ring][point][lon, lat]` (ring 0 is the
    /// outer boundary); a MultiPolygon nests one more level, one per part.
    /// Interior rings (holes) are dropped — irrelevant for a silhouette.
    private static func outerRings(of geometry: Geometry) -> [[CLLocationCoordinate2D]] {
        switch geometry.type {
        case "Polygon":
            guard case .array(let rings) = geometry.coordinates, let outer = rings.first else { return [] }
            return [coordinates(from: outer)]
        case "MultiPolygon":
            guard case .array(let polygons) = geometry.coordinates else { return [] }
            return polygons.compactMap { poly -> [CLLocationCoordinate2D]? in
                guard case .array(let rings) = poly, let outer = rings.first else { return nil }
                return coordinates(from: outer)
            }
        default:
            return []
        }
    }

    private static func coordinates(from ring: JSONValue) -> [CLLocationCoordinate2D] {
        guard case .array(let points) = ring else { return [] }
        return points.compactMap { point -> CLLocationCoordinate2D? in
            guard case .array(let lonLat) = point, lonLat.count >= 2,
                  case .number(let lon) = lonLat[0], case .number(let lat) = lonLat[1] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
}

/// Minimal recursive JSON value, just enough to walk GeoJSON's nested
/// coordinate arrays without pulling in a GeoJSON library.
indirect enum JSONValue: Decodable {
    case array([JSONValue])
    case number(Double)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .other
        }
    }
}
