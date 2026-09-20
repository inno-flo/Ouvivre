import SwiftUI
import MapKit

/// Étape 01 — Territoire: same full-bleed map presentation as Géographie 2
/// (GeoView2) — the country chips + facts float in a translucent column over
/// a MapKit background, with the camera kept shifted so the focused country
/// stays visible to the right of that column.
public struct PaysView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    @EnvironmentObject var mapState: MapPanelState
    @Environment(\.colorScheme) private var colorScheme
    let derived: ClassicDerived

    private var columnInk: Color { colorScheme == .dark ? Color(hex: 0xF4F2EE) : ClassicTheme.ink }
    private var columnFaint: Color { colorScheme == .dark ? Color(hex: 0xA39D91) : ClassicTheme.faint }

    @State private var position: MapCameraPosition = .automatic
    @State private var lastRegion: MKCoordinateRegion?
    @State private var transitionGeneration = 0

    private let columnWidth: CGFloat = 320
    private let columnOuterPadding: CGFloat = 20
    private let columnInnerPadding: CGFloat = 16

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Map(position: $position) {
                    Marker(mapState.title, coordinate: mapState.coordinate)
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
            Eyebrow("ÉTAPE 1", color: theme.accent)
            PaysCountryBlock(derived: derived, ink: columnInk, faint: columnFaint)
        }
        .padding(columnInnerPadding)
        .background(.regularMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var mapControlColumn: some View {
        VStack(spacing: 8) {
            MapPlanTypeMenuButton(planType: $mapState.planType)
            MapZoomStepper().opacity(0.75)
            MapPitchToggle()
                .mapControlVisibility(.visible)
                .opacity(0.75)
            MapCompass().opacity(0.75)
        }
    }

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

/// La liste de puces "pays" + fiche de faits — contenu de l'ÉTAPE 1, factorisé
/// hors de `PaysView` pour être réutilisé tel quel par `BigMacView` (bloc 1).
public struct PaysCountryBlock: View {
    @EnvironmentObject var state: ClassicState
    let derived: ClassicDerived
    let ink: Color
    let faint: Color
    /// `false` sur Big Mac : seules les capsules de choix du pays restent
    /// dans le bloc, la fiche de faits est déplacée dans l'inspecteur (voir
    /// `InspectorPanelView`/`ClassicRootView`).
    var showFacts: Bool = true
    var countryFont: Font = CFont.sans(13, weight: .medium)

    public init(derived: ClassicDerived, ink: Color, faint: Color, showFacts: Bool = true, countryFont: Font = CFont.sans(13, weight: .medium)) {
        self.countryFont = countryFont
        self.derived = derived
        self.ink = ink
        self.faint = faint
        self.showFacts = showFacts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(derived.countryList) { c in
                    Button { state.setCountry(c.name) } label: {
                        Text(c.name)
                            .font(countryFont)
                            .foregroundStyle(c.selected ? .white : ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(c.selected ? ClassicTheme.ink : .clear)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(c.selected ? ClassicTheme.ink : ClassicTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if showFacts {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(derived.countryFacts) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.key).font(CFont.sans(13)).foregroundStyle(faint)
                            Text(f.value).font(CFont.sans(15, weight: .medium)).foregroundStyle(ink)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

/// A responsive 2-column row that stacks to 1 column under `breakpoint`
/// points of available width — mirrors the dc export's CSS grids collapsing
/// naturally on narrow viewports. Implemented as a `Layout` (rather than a
/// `GeometryReader`) so it sizes correctly with variable-height children.
public struct AdaptiveTwoColumn<Left: View, Right: View>: View {
    var leftWeight: CGFloat = 1
    var rightWeight: CGFloat = 1
    var gap: CGFloat = 24
    var breakpoint: CGFloat = 640
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    public init(leftWeight: CGFloat = 1, rightWeight: CGFloat = 1, gap: CGFloat = 24, breakpoint: CGFloat = 640, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.leftWeight = leftWeight
        self.rightWeight = rightWeight
        self.gap = gap
        self.breakpoint = breakpoint
        self.left = left()
        self.right = right()
    }

    public var body: some View {
        TwoColumnLayout(leftWeight: leftWeight, rightWeight: rightWeight, gap: gap, breakpoint: breakpoint) {
            left
            right
        }
    }
}

struct TwoColumnLayout: Layout {
    var leftWeight: CGFloat
    var rightWeight: CGFloat
    var gap: CGFloat
    var breakpoint: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard subviews.count == 2 else { return .zero }
        if width < breakpoint {
            let l = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let r = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width, height: l.height + gap + r.height)
        } else {
            let lw = (width - gap) * leftWeight / (leftWeight + rightWeight)
            let rw = (width - gap) * rightWeight / (leftWeight + rightWeight)
            let l = subviews[0].sizeThatFits(ProposedViewSize(width: lw, height: nil))
            let r = subviews[1].sizeThatFits(ProposedViewSize(width: rw, height: nil))
            return CGSize(width: width, height: max(l.height, r.height))
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let width = bounds.width
        if width < breakpoint {
            let l = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: l.height))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + l.height + gap), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
        } else {
            let lw = (width - gap) * leftWeight / (leftWeight + rightWeight)
            let rw = (width - gap) * rightWeight / (leftWeight + rightWeight)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: lw, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + lw + gap, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: rw, height: nil))
        }
    }
}
