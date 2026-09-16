import SwiftUI
import MapKit

/// The "Carte" side panel — a MapKit view (via MapKit for SwiftUI) that
/// stays in sync with `MapPanelState`, animating a zoom-out/zoom-in transition
/// whenever the focused place changes (country in Pays, région in Géographie).
public struct MapPanelView: View {
    @ObservedObject var mapState: MapPanelState
    @State private var position: MapCameraPosition = .automatic
    @State private var lastRegion: MKCoordinateRegion?

    public init(mapState: MapPanelState) {
        self.mapState = mapState
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Map(position: $position) {
                Marker(mapState.title, coordinate: mapState.coordinate)
            }
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
