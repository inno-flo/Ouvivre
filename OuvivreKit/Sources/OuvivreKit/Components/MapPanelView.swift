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

/// A round map-type selector, styled to match MapKit's own native controls
/// (`MapCompass`, `MapPitchToggle`, `MapZoomStepper`) so it can sit in the
/// same `.mapControls` stack as them — MapKit has no built-in equivalent for
/// switching between named map styles (Explorer/Voiture/Transports/Satellite),
/// so this fills that one gap without introducing a different-looking control.
struct MapPlanTypeMenuButton: View {
    @Binding var planType: MapPlanType
    var icon: String = "globe.desk"
    var tint: Color = .black

    var body: some View {
        Menu {
            ForEach(MapPlanType.allCases) { type in
                Button { planType = type } label: { Label(type.label, systemImage: type.icon) }
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
        }
        .menuIndicator(.hidden)
        .modifier(RoundMapControlStyle())
        .frame(width: 32, height: 32)
        .help("Type de carte")
    }
}

/// Circular, solid-opaque chrome matching MapKit's own native control
/// buttons (e.g. `MapZoomStepper`) — translucent glass/material reads as
/// "no background" next to their solid look, so this uses a plain opaque
/// fill on every OS version instead of the (translucent-by-design) glass
/// button style.
private struct RoundMapControlStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .background(Color.white, in: Circle())
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
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
    /// Ties `mapControlColumn`'s native controls (placed in a plain
    /// `.overlay`, for full custom layout) back to this specific `Map` —
    /// without it they're inert (zoom +/− do nothing) and MapKit still
    /// shows its own default, unwired compass underneath ours.
    @Namespace private var mapScope

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
            .mapStyle(mapState.planType.style(elevation: .automatic))
            .mapControls {}
            .mapScope(mapScope)
            .overlay(alignment: .topTrailing) { mapControlColumn.padding(10) }
            .onMapCameraChange { context in lastRegion = context.region }
        }
        .frame(maxHeight: .infinity)
        .background(ClassicTheme.sidebarBg)
        .onAppear { moveCamera(animated: false) }
        .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(animated: true) }
        .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(animated: true) }
    }

    /// A single, explicit vertical column (rather than the default
    /// `.mapControls` auto-layout, which was inconsistently omitting
    /// `MapPitchToggle`/the custom menu button) so the four controls always
    /// appear together, top-trailing, in this fixed order — type de carte,
    /// zoom, 2D/3D, compas — at the same opacity as the settings block.
    private var mapControlColumn: some View {
        VStack(spacing: 8) {
            MapPlanTypeMenuButton(planType: $mapState.planType, tint: .black)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
            customZoomControl
            MapPitchToggle(scope: mapScope)
                .mapControlVisibility(.visible)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
            MapCompass(scope: mapScope)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
        }
        .tint(.black)
    }

    /// The native `MapZoomStepper` never responded to clicks here — even
    /// wired via `.mapScope` — so this drives the camera directly instead:
    /// guaranteed to work since it's entirely our own code.
    private var customZoomControl: some View {
        VStack(spacing: 0) {
            Button { zoom(by: 0.5) } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(.black)
                    .frame(width: 32, height: 26)
            }
            Divider().frame(width: 20)
            Button { zoom(by: 2) } label: {
                Image(systemName: "minus").font(.system(size: 13, weight: .medium)).foregroundStyle(.black)
                    .frame(width: 32, height: 26)
            }
        }
        .buttonStyle(.plain)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    private func zoom(by factor: Double) {
        guard let region = lastRegion else { return }
        let newRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.002, region.span.latitudeDelta * factor),
                longitudeDelta: max(0.002, region.span.longitudeDelta * factor)
            )
        )
        withAnimation(.easeInOut(duration: 0.25)) { position = .region(newRegion) }
        lastRegion = newRegion
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
