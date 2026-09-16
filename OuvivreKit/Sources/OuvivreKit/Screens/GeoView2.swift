import SwiftUI
import MapKit

/// Étape 02 (variante) — Géographie 2: an experimental single-pane layout.
/// There is no separate settings column or map inspector — the criteria
/// sliders float in a translucent column over a full-bleed MapKit
/// background, and the camera is kept shifted so the focused point of
/// interest always stays visible to the right of that column.
public struct GeoView2: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    @EnvironmentObject var mapState: MapPanelState
    let derived: ClassicDerived

    @State private var position: MapCameraPosition = .automatic
    @State private var lastTarget: MKCoordinateRegion?
    @State private var transitionGeneration = 0

    private let columnWidth: CGFloat = 320

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Map(position: $position) {
                    Marker(mapState.title, coordinate: mapState.coordinate)
                }
                .mapStyle(.standard(elevation: .flat))
                .mapControls { MapCompass() }
                .ignoresSafeArea(edges: [.horizontal, .bottom])

                settingsColumn
                    .frame(width: columnWidth)
                    .padding(20)
            }
            .onAppear { moveCamera(totalWidth: geo.size.width, animated: false) }
            .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: geo.size.width) { _, newValue in moveCamera(totalWidth: newValue, animated: false) }
        }
    }

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("ÉTAPE 02 BIS — GÉOGRAPHIE · FRANCE", color: theme.accent)
            VStack(alignment: .leading, spacing: 8) {
                exclusionToggle("Exclure les Territoires ultramarins", isOn: $state.excludeOverseas)
                exclusionToggle("Exclure la Corse", isOn: $state.excludeCorse)
            }
            ForEach(derived.geoRows) { row in
                CriterionRow(row: row) { state.setGeo(row.id, value: $0) }
            }
            HStack(spacing: 8) {
                OutlineButton("RÉINITIALISER") { state.resetGeo() }
                AccentButton("Valider →", fill: theme.accent) { state.go(.meteo) }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private func exclusionToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn.wrappedValue ? theme.accent : .white)
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(isOn.wrappedValue ? theme.accent : ClassicTheme.border, lineWidth: 1))
                    .overlay {
                        if isOn.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                Text(label).font(CFont.sans(13)).foregroundStyle(ClassicTheme.body)
            }
        }
        .buttonStyle(.plain)
    }

    /// Shifts the camera center west of the focused coordinate so the
    /// marker renders roughly centered in the space to the right of the
    /// settings column, instead of behind it.
    private func moveCamera(totalWidth: CGFloat, animated: Bool) {
        guard totalWidth > 0 else { return }
        let columnFraction = min(0.85, (columnWidth + 40) / totalWidth)
        let desiredScreenFraction = columnFraction + (1 - columnFraction) / 2
        let span = mapState.spanDegrees
        let lonShift = (desiredScreenFraction - 0.5) * span

        let target = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: mapState.coordinate.latitude,
                longitude: mapState.coordinate.longitude - lonShift
            ),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )

        guard animated, let old = lastTarget else {
            position = .region(target)
            lastTarget = target
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
        lastTarget = target
    }
}
