import Foundation
import CoreLocation

/// Drives the "Carte" side panel — its visibility (toggled from the panel's
/// own button or the Présentation ▸ Afficher/Masquer la carte menu item) and
/// the place it's currently focused on (a country in Pays, a région in
/// Géographie).
@MainActor
public final class MapPanelState: ObservableObject {
    /// Single shared instance so the app-level menu command and the panel
    /// view (owned deeper in `ClassicRootView`) stay in sync without
    /// threading a binding across the SwiftUI/App boundary.
    public static let shared = MapPanelState()

    @Published public var isVisible: Bool = true
    @Published public var title: String = "France"
    @Published public var coordinate: CLLocationCoordinate2D
    @Published public var spanDegrees: Double

    public init() {
        let place = GeoCoordinates.countries["France"]!
        coordinate = place.coordinate
        spanDegrees = place.span
    }

    public func focusOnCountry(_ name: String) {
        guard let place = GeoCoordinates.countries[name] else { return }
        title = name
        coordinate = place.coordinate
        spanDegrees = place.span
    }

    public func focusOnRegion(_ nomRegion: String) {
        guard let place = GeoCoordinates.regions[nomRegion] else { return }
        title = nomRegion
        coordinate = place.coordinate
        spanDegrees = place.span
    }
}
