import SwiftUI
import MapKit

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TopContentHeightKey: PreferenceKey {
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
    @Environment(\.colorScheme) private var colorScheme
    let derived: ClassicDerived

    /// The settings column sits on a translucent system material, which
    /// tints dark in system Dark Mode — unlike the rest of the app's fixed
    /// light palette, its text needs to flip to off-white there to stay
    /// legible.
    private var columnInk: Color { colorScheme == .dark ? Color(hex: 0xF4F2EE) : ClassicTheme.ink }
    private var columnBody: Color { colorScheme == .dark ? Color(hex: 0xD9D4C9) : ClassicTheme.body }
    private var columnFaint: Color { colorScheme == .dark ? Color(hex: 0xA39D91) : ClassicTheme.faint }

    @State private var position: MapCameraPosition = .automatic
    @State private var lastRegion: MKCoordinateRegion?
    @State private var transitionGeneration = 0
    @State private var otherRegionsContentHeight: CGFloat = 0
    @State private var topContentHeight: CGFloat = 0

    private let columnWidth: CGFloat = 320
    private let columnOuterPadding: CGFloat = 20
    private let columnInnerPadding: CGFloat = 16
    /// Reserved regardless of whether the chevron actually shows, so the
    /// scroll budget doesn't depend on its own visibility.
    private let chevronReserve: CGFloat = 18
    private let regionsHeaderReserve: CGFloat = 22

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
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
                .overlay(alignment: .topTrailing) { mapControlColumn.padding(10) }
                .onMapCameraChange { context in lastRegion = context.region }
                .ignoresSafeArea(edges: [.horizontal, .bottom])

                settingsColumn(columnAvailableHeight: geo.size.height - columnOuterPadding * 2)
                    .frame(width: columnWidth)
                    .padding(columnOuterPadding)
            }
            .onAppear { moveCamera(totalWidth: geo.size.width, animated: false) }
            .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: geo.size.width) { _, newValue in moveCamera(totalWidth: newValue, animated: false) }
        }
    }

    /// The column shrinks to fit its content (so a short "autres régions"
    /// list doesn't force it to full window height) but never grows past
    /// `columnAvailableHeight` — "autres régions" is the one flexible piece,
    /// sized to `min(its own content, whatever room is left)`.
    private func settingsColumn(columnAvailableHeight: CGFloat) -> some View {
        let chrome = columnInnerPadding * 2 + 12 /* spacing before the list */ + chevronReserve + regionsHeaderReserve
        let scrollBudget = max(60, columnAvailableHeight - chrome - topContentHeight)

        return VStack(alignment: .leading, spacing: 12) {
            topContent
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TopContentHeightKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(TopContentHeightKey.self) { topContentHeight = $0 }

            otherRegionsCard(maxHeight: scrollBudget)
        }
        .padding(columnInnerPadding)
        .background(.regularMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var topContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("ÉTAPE 02 BIS", color: theme.accent)
            VStack(alignment: .leading, spacing: 8) {
                exclusionToggle("Exclure les Territoires ultramarins", isOn: $state.excludeOverseas)
                exclusionToggle("Exclure la Corse", isOn: $state.excludeCorse)
            }
            Eyebrow("PROXIMITÉS", color: columnFaint).padding(.top, 4)
            ForEach(derived.geo2Rows) { row in
                CriterionRow(row: row, labelColor: columnInk) { state.setGeo2(row.id, value: $0) }
            }

            regionHero.padding(.top, 8)
        }
    }

    private var regionHero: some View {
        Button {
            if let nomRegion = derived.winningRegion(weights: state.geo2)?.nomRegion { mapState.focusOnRegion(nomRegion) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("RÉGION LA PLUS PROBANTE", color: ClassicTheme.darkPanelFaint).padding(.bottom, 8)
                Text(derived.winningRegion(weights: state.geo2)?.nomRegion ?? "—").font(CFont.sans(20, weight: .semibold)).foregroundStyle(.white)
                Text("Département le plus probant : \(derived.winningRegion(weights: state.geo2)?.bestDept ?? "—")")
                    .font(CFont.sans(12)).foregroundStyle(ClassicTheme.darkPanelSub).padding(.top, 4)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(derived.topScore(weights: state.geo2))").font(CFont.mono(24, weight: .medium)).foregroundStyle(theme.accentLight)
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

    /// Shrinks to fit its own list when short; scrolls internally, capped at
    /// `maxHeight` (the room left in the column), with a down chevron only
    /// when there's still more to see than fits. `maxHeight` is a ceiling,
    /// not a forced size — ScrollView sizes to its content up to that
    /// ceiling on its own, so a short list doesn't pad out to empty space.
    private func otherRegionsCard(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("AUTRES DÉPARTEMENTS", color: columnFaint).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(derived.regionRows(weights: state.geo2)) { r in
                        Button {
                            mapState.focusOnDepartement(r.name)
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(r.score)").font(CFont.mono(12, weight: .medium)).foregroundStyle(columnInk).frame(width: 20, alignment: .leading)
                                Text(r.name).font(CFont.sans(14, weight: .medium)).foregroundStyle(columnInk)
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
            .frame(maxHeight: maxHeight)
            .onPreferenceChange(ContentHeightKey.self) { otherRegionsContentHeight = $0 }

            if otherRegionsContentHeight > maxHeight {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(columnFaint)
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
                Text(label).font(CFont.sans(13)).foregroundStyle(columnBody)
            }
        }
        .buttonStyle(.plain)
    }

    /// A single, explicit vertical column (rather than the default
    /// `.mapControls` auto-layout, which was inconsistently omitting
    /// `MapPitchToggle`/the custom menu button) so the four controls always
    /// appear together, top-trailing, in this fixed order — type de carte,
    /// zoom, 2D/3D, compas — at the same opacity as `settingsColumn`.
    private var mapControlColumn: some View {
        VStack(spacing: 8) {
            MapPlanTypeMenuButton(planType: $mapState.planType)
            MapZoomStepper().opacity(0.75)
            MapPitchToggle()
                .mapControlVisibility(.visible)
                .opacity(0.75)
            MapCompass().opacity(0.75)
        }
        .tint(.black)
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
