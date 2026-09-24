import CoreLocation

/// Centroid coordinates for the map panel — countries (Pays view) and
/// French régions (Géographie view). Spans are degrees of latitude/longitude
/// used as the camera's zoom level when focusing that place.
public enum GeoCoordinates {
    public struct Place {
        public let coordinate: CLLocationCoordinate2D
        public let span: Double
        public init(_ lat: Double, _ lon: Double, span: Double) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            self.span = span
        }
    }

    public static let countries: [String: Place] = [
        "France": Place(46.6, 2.5, span: 9),
        "Danemark": Place(56.0, 10.0, span: 4.5),
        "Suède": Place(62.0, 15.0, span: 11),
        "Japon": Place(36.5, 138.0, span: 13)
    ]
}
