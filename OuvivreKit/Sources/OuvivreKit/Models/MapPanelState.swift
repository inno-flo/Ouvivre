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
    /// The plan type shown in the panel — lifted here (rather than local
    /// `@State` on `MapPanelView`) so the real macOS toolbar (in
    /// `ClassicRootView`, with genuine Liquid Glass chrome) can drive it too.
    @Published public var planType: MapPlanType = .explorer
    /// The focused région's real perimeter (one ring per landmass), if any —
    /// empty outside Géographie/Géographie 2, or for a place with no
    /// boundary data (a country, or a région not found).
    @Published public var regionRings: [[CLLocationCoordinate2D]] = []

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
        regionRings = []
    }

    public func focusOnRegion(_ nomRegion: String) {
        guard let place = GeoCoordinates.regions[nomRegion] else { return }
        title = nomRegion
        coordinate = place.coordinate
        spanDegrees = place.span
        regionRings = RegionBoundaries.rings[nomRegion] ?? []
    }

    /// Same idea as `focusOnRegion`, one administrative level finer — no
    /// hand-authored camera place exists for départements, so both the
    /// camera and the perimeter come from `DepartementBoundaries` (computed
    /// geometrically, see geo_pipeline).
    public func focusOnDepartement(_ nom: String) {
        guard let place = DepartementBoundaries.places[nom] else { return }
        title = nom
        coordinate = place.coordinate
        spanDegrees = place.span
        regionRings = DepartementBoundaries.rings[nom] ?? []
    }
}
