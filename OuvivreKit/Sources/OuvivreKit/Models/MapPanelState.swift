import Foundation
import CoreLocation

/// Drives the Sélecteur's map and inspector — the inspector's visibility
/// (toggled from the toolbar button or the Présentation ▸ Afficher/Masquer
/// l'inspecteur menu item) and the place the map is currently focused on.
@MainActor
public final class MapPanelState: ObservableObject {
    /// Single shared instance so the app-level menu command and the panel
    /// view (owned deeper in `ClassicRootView`) stay in sync without
    /// threading a binding across the SwiftUI/App boundary.
    public static let shared = MapPanelState()

    /// Règle : l'inspecteur est fermé par défaut. Il ne s'ouvre que sur
    /// action de l'utilisateur (bouton de la toolbar, menu) ou en cliquant
    /// un département affiché sur la carte du Sélecteur.
    @Published public var isVisible: Bool = false
    @Published var title: String = "France"
    @Published var coordinate: CLLocationCoordinate2D
    @Published var spanDegrees: Double
    /// The plan type shown in the panel — lifted here (rather than local
    /// `@State` on `SelecteurView`) so the real macOS toolbar (in
    /// `ClassicRootView`, with genuine Liquid Glass chrome) can drive it too.
    @Published var planType: MapPlanType = .explorer
    /// Départements tracés sur la carte, dans l'ordre de pertinence — leurs
    /// périmètres sont lus dans `DepartementBoundaries.rings`.
    @Published var departementNames: [String] = []
    /// Incrémenté à chaque demande de recentrage explicite : `coordinate`
    /// peut rester identique (l'utilisateur n'a fait que déplacer la carte),
    /// auquel cas aucun `onChange` sur la coordonnée ne se déclencherait.
    @Published var recenterTick: Int = 0

    private init() {
        let place = GeoCoordinates.countries["France"]!
        coordinate = place.coordinate
        spanDegrees = place.span
    }

    func focusOnCountry(_ name: String) {
        guard let place = GeoCoordinates.countries[name] else { return }
        title = name
        coordinate = place.coordinate
        spanDegrees = place.span
        departementNames = []
    }

    /// Recentre la caméra sur `coordinate` sans toucher aux périmètres
    /// dessinés (contrairement à `focusOnCountry`, qui les efface) ni au titre.
    func recenter(on coordinate: CLLocationCoordinate2D, span: Double) {
        self.coordinate = coordinate
        spanDegrees = span
        recenterTick += 1
    }

    func recenterOnCountry(_ name: String) {
        guard let place = GeoCoordinates.countries[name] else { return }
        recenter(on: place.coordinate, span: place.span)
    }

    /// Drive the toolbar's separate zoom-in/zoom-out buttons — halves/
    /// doubles the span, clamped so it can't zoom past street level or
    /// wider than the globe.
    func zoomIn() { spanDegrees = max(0.005, spanDegrees * 0.5) }
    func zoomOut() { spanDegrees = min(60, spanDegrees * 2) }
}
