import SwiftUI
import MapKit

/// Cadre contenant une carte centrée sur un département (périmètre tracé,
/// ajusté pour occuper au mieux le cadre), avec deux boutons de type de
/// carte (Explorer / Satellite), deux boutons de zoom et un bouton de
/// recentrage. Partagé par les fenêtres de détail Météo et Culture.
public struct DepartementMapCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }
    /// Départements mis en surbrillance (un seul dans les fenêtres de détail,
    /// tous les favoris dans l'écran Favoris).
    let names: [String]
    let accent: Color
    /// Département sélectionné (tracé plus marqué) et rappel au clic sur un
    /// département de la carte — utilisés par l'écran Favoris seulement.
    var selectedName: String?
    var onSelect: ((String) -> Void)?
    var height: CGFloat = 460
    /// Ordre des boutons : recentrage, zoom −, zoom +, puis Explorer/Satellite.
    var actionsFirst = false

    /// Demande de centrage sur un point (chef-lieu) : la carte s'y recentre
    /// à chaque incrément de `focusTick`.
    var focusCoordinate: CLLocationCoordinate2D?
    var focusTick = 0
    /// Police SF Pro Rounded pour les textes de la carte (fenêtre Culture).
    var roundedFont = false
    /// `false` dans les fenêtres Météo et Culture : périmètre tracé seul, sans voile.
    var fillsDepartement = true

    @State private var hoveredName: String?
    @State private var mapType: MapPlanType = .explorer
    @State private var mapPosition: MapCameraPosition = .automatic
    /// Dernière région affichée, pour que les boutons de zoom partent de la
    /// vue courante (déplacement manuel compris).
    @State private var mapRegion: MKCoordinateRegion?

    public init(name: String, accent: Color, focusCoordinate: CLLocationCoordinate2D? = nil, focusTick: Int = 0, roundedFont: Bool = false) {
        self.roundedFont = roundedFont
        self.names = [name]
        self.accent = accent
        self.actionsFirst = true
        self.fillsDepartement = false
        self.focusCoordinate = focusCoordinate
        self.focusTick = focusTick
    }

    public init(names: [String], accent: Color, selectedName: String? = nil, onSelect: ((String) -> Void)? = nil, height: CGFloat = 460, actionsFirst: Bool = false, roundedFont: Bool = false) {
        self.roundedFont = roundedFont
        self.names = names
        self.accent = accent
        self.selectedName = selectedName
        self.onSelect = onSelect
        self.height = height
        self.actionsFirst = actionsFirst
    }

    private static func contains(_ ring: [CLLocationCoordinate2D], _ p: CLLocationCoordinate2D) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.latitude > p.latitude) != (b.latitude > p.latitude),
               p.longitude < (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func departementName(at coordinate: CLLocationCoordinate2D) -> String? {
        names.first { name in (DepartementBoundaries.rings[name] ?? []).contains { Self.contains($0, coordinate) } }
    }

    private var allRings: [[CLLocationCoordinate2D]] { names.flatMap { DepartementBoundaries.rings[$0] ?? [] } }

    /// Rectangle englobant le périmètre du département, avec une petite
    /// marge — la carte s'y ajuste pour que le département occupe au mieux
    /// le cadre.
    private var departementRect: MKMapRect? {
        let points = allRings.flatMap { $0 }.map { MKMapPoint($0) }
        guard let first = points.first else { return names.isEmpty ? Self.franceRect : nil }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for pt in points.dropFirst() { rect = rect.union(MKMapRect(origin: pt, size: MKMapSize(width: 0, height: 0))) }
        return rect.insetBy(dx: -rect.width * 0.04, dy: -rect.height * 0.04)
    }

    /// Vue d'ensemble de la France métropolitaine, quand rien n'est sélectionné.
    private static let franceRect: MKMapRect = {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: 51.5, longitude: -5.5))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: 41.0, longitude: 10.0))
        return MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }()

    /// Cadre la carte sur tous les départements affichés, au zoom le plus fort
    /// qui les garde tous visibles. Repasse d'abord par la vue courante pour que
    /// le cadrage soit réappliqué même si la position mémorisée est déjà ce
    /// rectangle (après un déplacement ou un zoom manuel).
    private func fitSelection() {
        guard let rect = departementRect else { return }
        if let current = mapRegion { mapPosition = .region(current) }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) { mapPosition = .rect(rect) }
        }
    }

    private func zoomMap(by factor: Double) {
        guard let r = mapRegion else { return }
        let updated = MKCoordinateRegion(center: r.center, span: MKCoordinateSpan(
            latitudeDelta: min(170, max(0.002, r.span.latitudeDelta * factor)),
            longitudeDelta: min(360, max(0.002, r.span.longitudeDelta * factor))))
        withAnimation(.easeInOut(duration: 0.25)) { mapPosition = .region(updated) }
        mapRegion = updated
    }

    /// Nom et région du département survolé, à défaut du département sélectionné
    /// (clic sur la carte ou sur une colonne) — carte des favoris, sur une ligne, alignés à
    /// gauche, dans le style de l'en-tête de colonne du tableau.
    @ViewBuilder
    private var hoverLabel: some View {
        if let shown = hoveredName ?? selectedName, let dep = FranceGeoData.departements.first(where: { $0.nom == shown }) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dep.nom).font(CFont.rounded(13, weight: .semibold)).foregroundStyle(c.ink)
                // Pastille du code, comme dans l'inspecteur (20 pt) mais à l'échelle de 13 pt.
                Text(dep.codeInsee)
                    .font(CFont.rounded(13, weight: .semibold))
                    .foregroundStyle(c.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background((c.dark ? Color.white.opacity(0.12) : c.border.opacity(0.5)), in: RoundedRectangle(cornerRadius: 3.5))
                Text(dep.nomRegion).font(CFont.rounded(10)).foregroundStyle(c.faint)
            }
        }
    }

    private var typeButtons: some View {
        ForEach([MapPlanType.explorer, MapPlanType.satellite]) { type in
            Button { mapType = type } label: {
                Text(type.label)
                    .font(roundedFont ? CFont.rounded(12, weight: .medium) : CFont.sans(12, weight: .medium))
                    .foregroundStyle(mapType == type ? .white : c.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(mapType == type ? accent : .clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(mapType == type ? accent : c.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Afficher la carte \(type.label)")
        }
    }

    /// Recentrage, zoom −, zoom + — dans cet ordre quand `actionsFirst`, sinon
    /// zoom −, zoom +, recentrage.
    @ViewBuilder
    private var actionButtons: some View {
        let recenter = Button {
            fitSelection()
        } label: { Image(systemName: "mappin.and.ellipse").modifier(ActionIconSize(enlarged: actionsFirst)) }
            .buttonStyle(.plain).foregroundStyle(c.ink).help("Recentrer la carte")
        if actionsFirst { recenter }
        Button { zoomMap(by: 2) } label: { Image(systemName: "minus.magnifyingglass").modifier(ActionIconSize(enlarged: actionsFirst)) }
            .buttonStyle(.plain).foregroundStyle(c.ink).help("Dézoomer")
        Button { zoomMap(by: 0.5) } label: { Image(systemName: "plus.magnifyingglass").modifier(ActionIconSize(enlarged: actionsFirst)) }
            .buttonStyle(.plain).foregroundStyle(c.ink).help("Zoomer")
        if !actionsFirst { recenter }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                hoverLabel
                Spacer()
                if actionsFirst { actionButtons }
                typeButtons
                if !actionsFirst { actionButtons }
            }
            if departementRect != nil {
                MapReader { proxy in
                    Map(position: $mapPosition) {
                        ForEach(names, id: \.self) { name in
                            let selected = name == selectedName
                            let hovered = name == hoveredName
                            ForEach(Array((DepartementBoundaries.rings[name] ?? []).enumerated()), id: \.offset) { _, ring in
                                MapPolygon(coordinates: ring)
                                    .foregroundStyle(fillsDepartement ? accent.mapTrace(dark: c.dark).opacity(hovered ? 0.085 : 0.05) : .clear)
                                    .stroke(accent.mapTrace(dark: c.dark), lineWidth: selected ? 3 : 2)
                            }
                        }
                    }
                    .mapStyle(mapType.style(elevation: .automatic))
                    .mapControls {}
                    // Survol : mêmes règles d'opacité que la carte de Big Mac Tests
                    // (remplissage 0,05, ou 0,085 sous le curseur).
                    .onContinuousHover { phase in
                        guard onSelect != nil else { return }
                        switch phase {
                        case .active(let point):
                            hoveredName = proxy.convert(point, from: .local).flatMap { departementName(at: $0) }
                        case .ended:
                            hoveredName = nil
                        }
                    }
                    .onTapGesture { point in
                        guard let onSelect, let coordinate = proxy.convert(point, from: .local),
                              let name = departementName(at: coordinate) else { return }
                        onSelect(name)
                    }
                    .onMapCameraChange { context in mapRegion = context.region }
                }
                .onAppear { if let rect = departementRect { mapPosition = .rect(rect) } }
                .onChange(of: focusTick) { _, _ in
                    guard let coordinate = focusCoordinate else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        mapPosition = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                    }
                }
                // Sélection modifiée (favori ajouté/retiré) : le cadrage suit
                // pour garder tous les départements sélectionnés visibles.
                .onChange(of: names) { _, _ in
                    fitSelection()
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Carte indisponible pour ce département.")
                    .font(roundedFont ? CFont.rounded(13) : CFont.sans(13)).foregroundStyle(c.faint)
            }
        }
        .padding(16)
        .background(c.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.border, lineWidth: 1))
    }
}

/// Hauteur des boutons icônes de la carte : alignée sur celle des boutons
/// Explorer / Satellite (texte 12 pt + 5 pt de marge verticale) quand
/// `enlarged`, taille d'origine sinon.
private struct ActionIconSize: ViewModifier {
    let enlarged: Bool
    func body(content: Content) -> some View {
        if enlarged {
            content.font(.system(size: 15)).frame(width: 25, height: 25)
        } else {
            content
        }
    }
}
