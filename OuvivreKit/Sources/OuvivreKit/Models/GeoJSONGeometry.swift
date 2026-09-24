import Foundation
import CoreLocation

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

struct GeoJSONGeometry: Decodable {
    let type: String
    let coordinates: JSONValue
}

/// A Polygon's coordinates are `[ring][point][lon, lat]` (ring 0 is the
/// outer boundary); a MultiPolygon nests one more level, one per part.
/// Interior rings (holes) are dropped — irrelevant for a silhouette. Used
/// by DepartementBoundaries.
func geoJSONOuterRings(of geometry: GeoJSONGeometry) -> [[CLLocationCoordinate2D]] {
    switch geometry.type {
    case "Polygon":
        guard case .array(let rings) = geometry.coordinates, let outer = rings.first else { return [] }
        return [geoJSONCoordinates(from: outer)]
    case "MultiPolygon":
        guard case .array(let polygons) = geometry.coordinates else { return [] }
        return polygons.compactMap { poly -> [CLLocationCoordinate2D]? in
            guard case .array(let rings) = poly, let outer = rings.first else { return nil }
            return geoJSONCoordinates(from: outer)
        }
    default:
        return []
    }
}

private func geoJSONCoordinates(from ring: JSONValue) -> [CLLocationCoordinate2D] {
    guard case .array(let points) = ring else { return [] }
    return points.compactMap { point -> CLLocationCoordinate2D? in
        guard case .array(let lonLat) = point, lonLat.count >= 2,
              case .number(let lon) = lonLat[0], case .number(let lat) = lonLat[1] else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
