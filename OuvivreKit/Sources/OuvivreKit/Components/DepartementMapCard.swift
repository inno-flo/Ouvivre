import SwiftUI
import MapKit
#if os(macOS)
import AppKit
#endif

/// Cadre contenant une carte centrée sur un département (périmètre tracé,
/// ajusté pour occuper au mieux le cadre), avec deux boutons de type de
/// carte (Explorer / Satellite), deux boutons de zoom et un bouton de
/// recentrage. Partagé par les fenêtres de détail Météo et Culture.
struct DepartementMapCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }
    /// Départements mis en surbrillance (un seul dans les fenêtres de détail,
    /// tous les favoris dans l'écran Favoris).
    let names: [String]
    /// Département sélectionné (tracé plus marqué) et rappel au clic sur un
    /// département de la carte — utilisés par l'écran Favoris seulement.
    var selectedName: String?
    var onSelect: ((String) -> Void)?
    var height: CGFloat = 460
    /// Demande de centrage sur un point (chef-lieu) : la carte s'y recentre
    /// à chaque incrément de `focusTick`.
    var focusCoordinate: CLLocationCoordinate2D?
    var focusTick = 0
    /// Emplacements des relevés de record de chaleur du mois sélectionné, repérés
    /// par un soleil rouge et l'année du relevé (couleur de la courbe des records) — fenêtre Climat.
    var pinMarks: [RecordPinMark] = []
    /// `false` dans les fenêtres Météo et Culture : périmètre tracé seul, sans voile.
    var fillsDepartement = true
    /// Poignée de redimensionnement au centre du bord inférieur du cadre : glisser vers
    /// le bas agrandit la carte (les sections en dessous suivent), double-clic
    /// revient à `height`, qui reste la hauteur minimale.
    var resizable = false

    @State private var hoveredName: String?
    /// Hauteur ajoutée à `height` par la poignée (jamais négative).
    @State private var extraHeight: CGFloat = 0
    @State private var dragStartExtra: CGFloat?
    @State private var mapType: MapPlanType = .explorer
    @State private var mapPosition: MapCameraPosition = .automatic
    /// Dernière région affichée, pour que les boutons de zoom partent de la
    /// vue courante (déplacement manuel compris).
    @State private var mapRegion: MKCoordinateRegion?

    /// Rectangle englobant le périmètre du département, avec une petite
    /// marge — la carte s'y ajuste pour que le département occupe au mieux
    /// le cadre.
    private var departementRect: MKMapRect? {
        let points = names.flatMap { DepartementBoundaries.rings[$0] ?? [] }.joined().map { MKMapPoint($0) }
        guard let first = points.first else { return nil }
        let rect = points.dropFirst().reduce(MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))) {
            $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 0, height: 0)))
        }
        return rect.insetBy(dx: -rect.width * 0.04, dy: -rect.height * 0.04)
    }

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
        if let shown = hoveredName ?? selectedName, let dep = FranceGeoData.byName[shown] {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dep.nom).font(CFont.rounded(13, weight: .semibold)).foregroundStyle(c.ink)
                // Pastille du code, comme dans l'inspecteur (20 pt) mais à l'échelle de 13 pt.
                Text(dep.codeInsee)
                    .font(CFont.rounded(13, weight: .semibold))
                    .foregroundStyle(c.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(c.badge, in: RoundedRectangle(cornerRadius: 3.5))
                Text(dep.nomRegion).font(CFont.rounded(10)).foregroundStyle(c.faint)
            }
        }
    }

    private var typeButtons: some View {
        ForEach([MapPlanType.explorer, MapPlanType.satellite]) { type in
            Button { mapType = type } label: {
                Text(type.label)
                    .font(CFont.rounded(12, weight: .medium))
                    .foregroundStyle(mapType == type ? .white : c.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(mapType == type ? ClassicTheme.accent : .clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(mapType == type ? ClassicTheme.accent : c.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Afficher la carte \(type.label)")
        }
    }

    /// Recentrage, zoom −, zoom + — hauteur des icônes alignée sur celle des
    /// boutons Explorer / Satellite (texte 12 pt + 5 pt de marge verticale).
    @ViewBuilder
    private var actionButtons: some View {
        actionButton("mappin.and.ellipse", help: "Recentrer la carte", action: fitSelection)
        actionButton("minus.magnifyingglass", help: "Dézoomer") { zoomMap(by: 2) }
        actionButton("plus.magnifyingglass", help: "Zoomer") { zoomMap(by: 0.5) }
    }

    private func actionButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15)).frame(width: 25, height: 25)
        }
        .buttonStyle(.plain).foregroundStyle(c.ink).help(help)
    }

    private var resizeHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(c.faint)
            // Zone de saisie plus large que l'icône, dans la marge basse du cadre.
            .frame(width: 56, height: 16)
            .contentShape(Rectangle())
            .help("Glisser pour agrandir la carte · double-clic pour revenir à la taille par défaut")
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            #endif
            // Coordonnées globales : la poignée suit le bord qui bouge, une
            // translation locale se mettrait à osciller.
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartExtra ?? extraHeight
                        dragStartExtra = start
                        extraHeight = max(0, start + value.translation.height)
                    }
                    .onEnded { _ in dragStartExtra = nil }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) { extraHeight = 0 }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                hoverLabel
                Spacer()
                actionButtons
                typeButtons
            }
            // Test léger (sans calculer le rectangle englobant à chaque survol).
            if names.contains(where: { !(DepartementBoundaries.rings[$0] ?? []).isEmpty }) {
                MapReader { proxy in
                    Map(position: $mapPosition) {
                        ForEach(pinMarks) { mark in
                            Annotation("", coordinate: mark.coordinate, anchor: .center) {
                                // L'année est en surimpression : elle ne décale pas
                                // l'icône, qui reste centrée sur le relevé.
                                Image(systemName: "sun.max.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(hex: 0xD1382E))
                                    .shadow(color: .white.opacity(0.9), radius: 2)
                                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                                    .overlay(alignment: .bottom) {
                                        Text(mark.years.map(String.init).joined(separator: ", "))
                                            .font(CFont.rounded(11, weight: .bold))
                                            .foregroundStyle(Color(hex: 0xD1382E))
                                            .shadow(color: .white, radius: 1.5)
                                            .shadow(color: .white, radius: 1.5)
                                            .fixedSize()
                                            .offset(y: 15)
                                    }
                                    .allowsHitTesting(false)
                            }
                        }
                        ForEach(names, id: \.self) { name in
                            let selected = name == selectedName
                            let hovered = name == hoveredName
                            ForEach(Array((DepartementBoundaries.rings[name] ?? []).enumerated()), id: \.offset) { _, ring in
                                MapPolygon(coordinates: ring)
                                    .foregroundStyle(fillsDepartement ? ClassicTheme.accent.mapTrace(dark: c.dark).opacity(hovered ? 0.085 : 0.05) : .clear)
                                    .stroke(ClassicTheme.accent.mapTrace(dark: c.dark), lineWidth: selected ? 3 : 2)
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
                            hoveredName = proxy.convert(point, from: .local).flatMap { DepartementBoundaries.departement(at: $0, among: names) }
                        case .ended:
                            hoveredName = nil
                        }
                    }
                    .onTapGesture { point in
                        guard let onSelect, let coordinate = proxy.convert(point, from: .local),
                              let name = DepartementBoundaries.departement(at: coordinate, among: names) else { return }
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
                .frame(height: height + extraHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Carte indisponible pour ce département.")
                    .font(CFont.rounded(13)).foregroundStyle(c.faint)
            }
        }
        .padding(16)
        .background(c.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.border, lineWidth: 1))
        // Poignée centrée dans le bord inférieur du cadre, sous la carte.
        .overlay(alignment: .bottom) { if resizable { resizeHandle } }
    }
}
