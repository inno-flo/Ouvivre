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

    /// Règle : l'inspecteur est fermé par défaut, sur tous les écrans. Il ne
    /// s'ouvre que sur action de l'utilisateur (bouton de la toolbar) ou,
    /// dans Big Mac, en cliquant un département affiché sur la carte.
    @Published public var isVisible: Bool = false
    /// Visibilité de l'inspecteur spécifique à Big Mac — séparée de
    /// `isVisible` pour ne pas dépendre du réglage des autres écrans.
    @Published public var bigMacInspectorVisible: Bool = false
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
    /// "Afficher sur la carte" on the top-N list — each département's rings
    /// kept separate (rather than flattened into `regionRings`) so the map
    /// can raise just the hovered one's shading.
    @Published public var departementRingGroups: [(name: String, rings: [[CLLocationCoordinate2D]])] = []

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
        departementRingGroups = []
    }

    public func focusOnRegion(_ nomRegion: String) {
        guard let place = GeoCoordinates.regions[nomRegion] else { return }
        title = nomRegion
        coordinate = place.coordinate
        spanDegrees = place.span
        regionRings = RegionBoundaries.rings[nomRegion] ?? []
        departementRingGroups = []
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
        departementRingGroups = []
    }

    /// Draws every named département's perimeter at once and zooms out to
    /// show all of France — "Afficher sur la carte" on the top-N list.
    public func focusOnDepartements(_ noms: [String]) {
        guard let france = GeoCoordinates.countries["France"] else { return }
        title = "France"
        coordinate = france.coordinate
        spanDegrees = france.span
        regionRings = []
        departementRingGroups = noms.map { ($0, DepartementBoundaries.rings[$0] ?? []) }
    }

    /// Clears whatever perimeter is drawn, without moving the camera —
    /// tapping the map to deselect the top-N départements.
    public func clearRegionRings() {
        regionRings = []
        departementRingGroups = []
    }

    /// Redraws the top-N départements' perimeters without touching the
    /// camera — keeps "Afficher sur la carte" in sync as weights change.
    public func updateDepartementRingGroups(_ noms: [String]) {
        departementRingGroups = noms.map { ($0, DepartementBoundaries.rings[$0] ?? []) }
    }

    /// Drive the toolbar's separate zoom-in/zoom-out buttons — halves/
    /// doubles the span, clamped so it can't zoom past street level or
    /// wider than the globe.
    public func zoomIn() { spanDegrees = max(0.005, spanDegrees * 0.5) }
    public func zoomOut() { spanDegrees = min(60, spanDegrees * 2) }
}
