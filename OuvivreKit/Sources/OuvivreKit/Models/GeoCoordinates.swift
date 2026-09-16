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

    /// Approximate centroid per région, keyed by `FranceGeoData` `nomRegion`.
    public static let regions: [String: Place] = [
        "Auvergne-Rhône-Alpes": Place(45.4, 4.4, span: 3.2),
        "Bourgogne-Franche-Comté": Place(47.05, 4.95, span: 3.0),
        "Bretagne": Place(48.2, -2.9, span: 2.4),
        "Centre-Val de Loire": Place(47.5, 1.7, span: 2.6),
        "Corse": Place(42.15, 9.1, span: 1.4),
        "Grand Est": Place(48.7, 5.5, span: 3.2),
        "Guadeloupe": Place(16.25, -61.55, span: 1.0),
        "Guyane": Place(4.0, -53.0, span: 3.5),
        "Hauts-de-France": Place(49.9, 2.8, span: 2.2),
        "La Réunion": Place(-21.1, 55.5, span: 1.0),
        "Martinique": Place(14.6, -61.0, span: 0.8),
        "Mayotte": Place(-12.8, 45.15, span: 0.6),
        "Normandie": Place(49.1, 0.3, span: 2.4),
        "Nouvelle-Aquitaine": Place(45.3, 0.2, span: 3.6),
        "Occitanie": Place(43.7, 2.0, span: 3.4),
        "Pays de la Loire": Place(47.5, -0.8, span: 2.4),
        "Provence-Alpes-Côte d'Azur": Place(43.95, 6.1, span: 2.6),
        "Île-de-France": Place(48.85, 2.35, span: 1.4)
    ]
}
