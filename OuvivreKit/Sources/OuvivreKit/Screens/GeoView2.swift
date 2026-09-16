import SwiftUI
import MapKit

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

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
    @State private var lastRegion: MKCoordinateRegion?
    @State private var transitionGeneration = 0
    @State private var planType: MapPlanType = .explorer
    @State private var is3D: Bool = false
    @State private var otherRegionsContentHeight: CGFloat = 0

    private let columnWidth: CGFloat = 320
    private let otherRegionsMaxHeight: CGFloat = 200

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Map(position: $position) {
                    Marker(mapState.title, coordinate: mapState.coordinate)
                }
                .mapStyle(planType.style(elevation: is3D ? .realistic : .flat))
                .mapControls { MapCompass() }
                .onMapCameraChange { context in lastRegion = context.region }
                .ignoresSafeArea(edges: [.horizontal, .bottom])
                .overlay(alignment: .topTrailing) { controlCluster.padding(10) }

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
            Eyebrow("PROXIMITÉS", color: ClassicTheme.faint).padding(.top, 4)
            ForEach(derived.geoRows) { row in
                CriterionRow(row: row) { state.setGeo(row.id, value: $0) }
            }

            regionHero.padding(.top, 8)
            otherRegionsCard
        }
        .padding(16)
        .background(.regularMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var regionHero: some View {
        Button {
            if let nomRegion = derived.winningRegion?.nomRegion { mapState.focusOnRegion(nomRegion) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("RÉGION LA PLUS PROBANTE", color: ClassicTheme.darkPanelFaint).padding(.bottom, 8)
                Text(derived.winningRegion?.nomRegion ?? "—").font(CFont.sans(20, weight: .semibold)).foregroundStyle(.white)
                Text("Département le plus probant : \(derived.winningRegion?.bestDept ?? "—")")
                    .font(CFont.sans(12)).foregroundStyle(ClassicTheme.darkPanelSub).padding(.top, 4)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(derived.topScore)").font(CFont.mono(24, weight: .medium)).foregroundStyle(theme.accentLight)
                    Text("/100 CORRESPONDANCE").font(CFont.mono(10)).foregroundStyle(ClassicTheme.darkPanelFaint)
                }
                .padding(.top, 10)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x2D2F36))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// Capped-height card so it always fits under the sliders; scrolls
    /// internally and shows a down chevron only when there's more to see.
    private var otherRegionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("AUTRES RÉGIONS", color: ClassicTheme.faint).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(derived.regionRows) { r in
                        Button {
                            mapState.focusOnRegion(r.nomRegion)
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(r.score)").font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.ink).frame(width: 20, alignment: .leading)
                                Text(r.name).font(CFont.sans(12, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .frame(maxHeight: otherRegionsMaxHeight)
            .onPreferenceChange(ContentHeightKey.self) { otherRegionsContentHeight = $0 }

            if otherRegionsContentHeight > otherRegionsMaxHeight {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ClassicTheme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
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

    // MARK: Map display controls (same as the inspector's MapPanelView)

    private var controlCluster: some View {
        VStack(spacing: 8) {
            mapStyleMenu
            zoomControl
            nativeControlButton(icon: is3D ? "view.2d" : "view.3d", active: is3D, help: is3D ? "Passer en 2D" : "Passer en 3D") {
                is3D.toggle()
            }
        }
    }

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
