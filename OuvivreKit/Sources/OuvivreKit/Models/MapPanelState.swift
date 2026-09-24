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
    /// "Afficher sur la carte" on the top-N list — each département's rings
    /// kept separate so the map can raise just the hovered one's shading.
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
        departementRingGroups = []
    }

    /// Incrémenté à chaque demande de recentrage explicite : `coordinate`
    /// peut rester identique (l'utilisateur n'a fait que déplacer la carte),
    /// auquel cas aucun `onChange` sur la coordonnée ne se déclencherait.
    @Published public var recenterTick: Int = 0

    /// Recentre la caméra sur le pays sans toucher aux périmètres dessinés
    /// (contrairement à `focusOnCountry`, qui les efface) ni au titre.
    public func recenterOnCountry(_ name: String) {
        guard let place = GeoCoordinates.countries[name] else { return }
        coordinate = place.coordinate
        spanDegrees = place.span
        recenterTick += 1
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
