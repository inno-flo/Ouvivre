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
    @State private var planType: MapPlanType = .explorer
    @State private var is3D: Bool = false

    public init(mapState: MapPanelState) {
        self.mapState = mapState
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Map(position: $position) {
                Marker(mapState.title, coordinate: mapState.coordinate)
            }
            .mapStyle(planType.style(elevation: is3D ? .realistic : .flat))
            .mapControls {
                MapZoomStepper()
                MapPitchToggle()
                MapCompass()
            }
            planTypePicker
        }
        .frame(maxHeight: .infinity)
        .background(ClassicTheme.sidebarBg)
        .onAppear { moveCamera(animated: false) }
        .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(animated: true) }
        .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(animated: true) }
    }

    private var header: some View {
        HStack {
            Text("CARTE")
                .font(CFont.mono(11, weight: .medium))
                .foregroundStyle(ClassicTheme.faint)
            Spacer()
            Button { is3D.toggle() } label: {
                Image(systemName: is3D ? "view.2d" : "view.3d")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClassicTheme.faint)
            }
            .buttonStyle(.plain)
            .help(is3D ? "Passer en 2D" : "Passer en 3D")
            Button { mapState.isVisible = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ClassicTheme.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.border).frame(height: 1) }
    }

    private var planTypePicker: some View {
        HStack(spacing: 4) {
            ForEach(MapPlanType.allCases) { type in
                Button { planType = type } label: {
                    VStack(spacing: 3) {
                        Image(systemName: type.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text(type.label)
                            .font(CFont.sans(10, weight: .medium))
                    }
                    .foregroundStyle(planType == type ? .white : ClassicTheme.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(planType == type ? ClassicTheme.ink : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .overlay(alignment: .top) { Rectangle().fill(ClassicTheme.border).frame(height: 1) }
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

        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(midRegion)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.45)) {
                position = .region(target)
            }
        }
        lastRegion = target
    }
}
