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
    @ObservedObject var mapState: MapPanelState
    @State private var position: MapCameraPosition = .automatic
    @State private var lastRegion: MKCoordinateRegion?
    @State private var transitionGeneration = 0
    @State private var planType: MapPlanType = .explorer
    @State private var is3D: Bool = false

    public init(mapState: MapPanelState) {
        self.mapState = mapState
    }

    public var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                Marker(mapState.title, coordinate: mapState.coordinate)
            }
            .mapStyle(planType.style(elevation: is3D ? .realistic : .flat))
            .mapControls {
                MapCompass()
            }
            .onMapCameraChange { context in lastRegion = context.region }
            .overlay(alignment: .topTrailing) { controlCluster.padding(10) }
        }
        .frame(maxHeight: .infinity)
        .background(ClassicTheme.sidebarBg)
        .onAppear { moveCamera(animated: false) }
        .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(animated: true) }
        .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(animated: true) }
    }

    /// Mirrors Apple Plans' standard control stack: a map-style menu, then
    /// zoom, then the 2D/3D toggle — all styled like MapKit's own controls.
    private var controlCluster: some View {
        VStack(spacing: 8) {
            mapStyleMenu
            zoomControl
            nativeControlButton(icon: is3D ? "view.2d" : "view.3d", active: is3D, help: is3D ? "Passer en 2D" : "Passer en 3D") {
                is3D.toggle()
            }
        }
    }

    /// Groups the four plan types (Explorer/Voiture/Transports/Satellite)
    /// behind one menu button, like Plans' layers picker, instead of four
    /// separate buttons always on screen.
    private var mapStyleMenu: some View {
        Menu {
            ForEach(MapPlanType.allCases) { type in
                Button { planType = type } label: { Label(type.label, systemImage: type.icon) }
            }
        } label: {
            Image(systemName: planType.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 29, height: 29)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .help("Type de carte")
    }

    private var zoomControl: some View {
        VStack(spacing: 0) {
            Button { zoom(by: 0.5) } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium)).frame(width: 29, height: 22)
            }
            Divider().frame(width: 18)
            Button { zoom(by: 2) } label: {
                Image(systemName: "minus").font(.system(size: 13, weight: .medium)).frame(width: 29, height: 22)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .help("Zoom")
    }

    private func nativeControlButton(icon: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .primary)
                .frame(width: 29, height: 29)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .help(help)
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
