import SwiftUI
import MapKit

/// The four plan types offered by the panel's type picker, mirroring Apple
/// Maps' own choices (Explorer / Conduite / Transports / Satellite).
public enum MapPlanType: String, CaseIterable, Identifiable {
    case explorer, voiture, transports, satellite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .explorer: "Explorer"
        case .voiture: "Voiture"
        case .transports: "Transports"
        case .satellite: "Satellite"
        }
    }

    public var icon: String {
        switch self {
        case .explorer: "map"
        case .voiture: "car"
        case .transports: "tram"
        case .satellite: "globe.americas"
        }
    }

    func style(elevation: MapStyle.Elevation) -> MapStyle {
        switch self {
        case .explorer: .standard(elevation: elevation)
        case .voiture: .standard(elevation: elevation, showsTraffic: true)
        case .transports: .standard(elevation: elevation, pointsOfInterest: .including([.publicTransport]))
        case .satellite: .hybrid(elevation: elevation)
        }
    }
}

/// The "Carte" side panel — a MapKit view (via MapKit for SwiftUI) that
/// stays in sync with `MapPanelState`, animating a zoom-out/zoom-in transition
/// whenever the focused place changes (country in Pays, région in Géographie).
/// Offers manual zoom, a 2D/3D toggle, and the four plan types.
public struct MapPanelView: View {
    @EnvironmentObject var theme: ClassicTheme
    @ObservedObject var mapState: MapPanelState
    @State private var position: MapCameraPosition = .automatic
    @State private var lastRegion: MKCoordinateRegion?
    @State private var transitionGeneration = 0
    @State private var planType: MapPlanType = .explorer

    public init(mapState: MapPanelState) {
        self.mapState = mapState
    }

    public var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                ForEach(Array(mapState.regionRings.enumerated()), id: \.offset) { _, ring in
                    MapPolygon(coordinates: ring)
                        .foregroundStyle(theme.accent.opacity(0.16))
                        .stroke(theme.accent, lineWidth: 2)
                }
                if mapState.regionRings.isEmpty {
                    Marker(mapState.title, coordinate: mapState.coordinate)
                }
            }
            .mapStyle(planType.style(elevation: .automatic))
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapZoomStepper()
            }
            .onMapCameraChange { context in lastRegion = context.region }
            .overlay(alignment: .topTrailing) { mapStyleMenu.padding(10) }
        }
        .frame(maxHeight: .infinity)
        .background(ClassicTheme.sidebarBg)
        .onAppear { moveCamera(animated: false) }
        .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(animated: true) }
        .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(animated: true) }
    }

    /// Groups the four plan types (Explorer/Voiture/Transports/Satellite)
    /// behind one system `Menu`, styled with the stock bordered control look
    /// (no hand-rolled material/border) — like Plans' own layers picker.
    /// Zoom (`MapZoomStepper`) and the 2D/3D toggle (`MapPitchToggle`) are
    /// MapKit's own native controls, added via `.mapControls` above.
    private var mapStyleMenu: some View {
        Menu {
            ForEach(MapPlanType.allCases) { type in
                Button { planType = type } label: { Label(type.label, systemImage: type.icon) }
            }
        } label: {
            Image(systemName: planType.icon)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help("Type de carte")
    }

    private func moveCamera(animated: Bool) {
        let target = MKCoordinateRegion(
            center: mapState.coordinate,
            span: MKCoordinateSpan(latitudeDelta: mapState.spanDegrees, longitudeDelta: mapState.spanDegrees)
        )
        guard animated, let old = lastRegion else {
            position = .region(target)
            lastRegion = target
            return
        }

        let midCoordinate = CLLocationCoordinate2D(
            latitude: (old.center.latitude + target.center.latitude) / 2,
            longitude: (old.center.longitude + target.center.longitude) / 2
        )
        let spread = max(old.span.latitudeDelta, target.span.latitudeDelta)
            + abs(old.center.latitude - target.center.latitude)
            + abs(old.center.longitude - target.center.longitude)
        let midRegion = MKCoordinateRegion(
            center: midCoordinate,
            span: MKCoordinateSpan(latitudeDelta: spread * 1.5, longitudeDelta: spread * 1.5)
        )

        // Chained via the first animation's completion (rather than a fixed
        // `asyncAfter` delay) so the dézoom → zoom sits on one continuous
        // timeline instead of drifting out of sync and visibly hitching.
        transitionGeneration += 1
        let generation = transitionGeneration

        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(midRegion)
        } completion: {
            guard generation == transitionGeneration else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                position = .region(target)
            }
        }
        lastRegion = target
    }
}
