import CoreLocation

/// Centroid coordinates for the map panel — countries (bloc Pays du
/// Sélecteur). Spans are degrees of latitude/longitude used as the
/// camera's zoom level when focusing that place.
enum GeoCoordinates {
    struct Place {
        let coordinate: CLLocationCoordinate2D
        let span: Double
        init(_ lat: Double, _ lon: Double, span: Double) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            self.span = span
        }
    }

    static let countries: [String: Place] = [
        "France": Place(46.6, 2.5, span: 9),
        "Danemark": Place(56.0, 10.0, span: 4.5),
        "Suède": Place(62.0, 15.0, span: 11),
        "Japon": Place(36.5, 138.0, span: 13)
    ]
}
