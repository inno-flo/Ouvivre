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
    @State private var showMoreDepartements = false

    private let columnWidth: CGFloat = 320
    private let columnOuterPadding: CGFloat = 20
    private let columnInnerPadding: CGFloat = 16
    private let topDepartementsCount = 10
    private let moreDepartementsMaxHeight: CGFloat = 220

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

                settingsColumn
                    .frame(width: columnWidth)
                    .padding(columnOuterPadding)
            }
            .onAppear { moveCamera(totalWidth: geo.size.width, animated: false) }
            .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: geo.size.width) { _, newValue in moveCamera(totalWidth: newValue, animated: false) }
        }
    }

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            topContent
            departementsCard
        }
        .padding(columnInnerPadding)
        .background(.regularMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var topContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("ÉTAPE 2", color: theme.accent)
            VStack(alignment: .leading, spacing: 8) {
                exclusionToggle("Exclure les Territoires ultramarins", isOn: $state.excludeOverseas)
                exclusionToggle("Exclure la Corse", isOn: $state.excludeCorse)
            }
            Eyebrow("PROXIMITÉS", color: columnFaint).padding(.top, 4)
            ForEach(derived.geo2Rows) { row in
                CriterionRow(row: row, labelColor: columnInk) { state.setGeo2(row.id, value: $0) }
            }

            // "Région la plus probante" masqué à titre de test — la logique
            // (`regionHero`) reste disponible ci-dessous, juste non affichée.
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

    /// All départements ranked 0...100 by the current proximity criteria —
    /// the top 10 always show; the rest sit behind a collapsible
    /// "Autres départements" header with a disclosure chevron.
    private var departementsCard: some View {
        let ranked = derived.rankedDepartements(weights: state.geo2)
        let top10 = Array(ranked.prefix(topDepartementsCount))
        let rest = Array(ranked.dropFirst(topDepartementsCount))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("DÉPARTEMENTS", color: columnFaint)
                Spacer()
                sortMenu
            }
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(top10, id: \.dep.nom) { entry in
                    departementRow(name: entry.dep.nom, score: entry.score)
                }
            }

            if !rest.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showMoreDepartements.toggle() }
                } label: {
                    HStack {
                        Eyebrow("AUTRES DÉPARTEMENTS", color: columnFaint)
                        Spacer()
                        Image(systemName: showMoreDepartements ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(columnFaint)
                    }
                    .padding(.top, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showMoreDepartements {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rest, id: \.dep.nom) { entry in
                                departementRow(name: entry.dep.nom, score: entry.score)
                            }
                        }
                    }
                    .frame(maxHeight: moreDepartementsMaxHeight)
                    .padding(.top, 8)
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Button("Département") {}
            Button("Région") {}
        } label: {
            HStack(spacing: 4) {
                Text("Classer").font(CFont.sans(11, weight: .medium))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(columnFaint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func departementRow(name: String, score: Double) -> some View {
        Button {
            mapState.focusOnDepartement(name)
        } label: {
            HStack(spacing: 10) {
                Text("\(Int(score.rounded()))").font(CFont.mono(12, weight: .medium)).foregroundStyle(columnInk).frame(width: 20, alignment: .leading)
                Text(name).font(CFont.sans(14, weight: .medium)).foregroundStyle(columnInk)
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
