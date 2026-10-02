import SwiftUI
import MapKit

/// "Big Mac" (nom provisoire) — présentation plein cadre
/// (fond MapKit + colonne flottante translucide), mais la colonne empile 2
/// blocs rétractables (`DisclosureGroup`) qui reprennent, dans l'ordre,
/// Pays → Géographie et Culture (tailles de commune, proximités, Culture). Chaque bloc
/// hérite de l'état partagé `ClassicState`, donc les choix persistent d'un
/// bloc à l'autre ; les blocs sont indépendants (pas d'entonnoir) : chaque réglage
/// met à jour la carte en direct.
struct SelecteurView: View {
    @EnvironmentObject var state: ClassicState
    @EnvironmentObject var mapState: MapPanelState
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }

    private var blockFill: Color { colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.528) }
    private var blockStroke: Color { colorScheme == .dark ? Color.white.opacity(0.15) : ClassicTheme.border.opacity(0.6) }

    @State private var position: MapCameraPosition = .automatic
    @State private var lastRegion: MKCoordinateRegion?
    @State private var transitionGeneration = 0
    /// Département actuellement survolé — rend son polygone opaque. MapKit ne
    /// propose pas de survol par forme, donc on hit-teste manuellement le
    /// point de la souris contre les polygones via `MapReader`.
    @State private var hoveredDepartementName: String?
    /// Département cliqué, dont le polygone reste opaque tant qu'on ne
    /// clique pas ailleurs (contrairement au survol, transitoire).
    @State private var selectedDepartementName: String?

    // L'ouverture/fermeture des blocs vit dans `ClassicState` (pas un
    // `@State` local) pour rester persistante en quittant puis en revenant
    // sur cet écran — sinon `SelecteurView` est recréée à chaque fois et tout
    // se replie.

    /// Vrai pendant l'application du dépli par défaut à l'apparition.
    @State private var isApplyingDefaultExpansion = false

    private let columnWidth: CGFloat = 420
    private let columnOuterPadding: CGFloat = 20
    private let columnInnerPadding: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                MapReader { proxy in
                    Map(position: $position) { mapContent }
                        .mapStyle(mapState.planType.style(elevation: .automatic))
                        .mapControls {}
                        .onMapCameraChange { context in lastRegion = context.region }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                hoveredDepartementName = departementName(at: point, proxy: proxy)
                            case .ended:
                                hoveredDepartementName = nil
                            }
                        }
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                if let name = departementName(at: value.location, proxy: proxy) {
                                    selectedDepartementName = name
                                    mapState.title = name
                                    withAnimation(.easeInOut(duration: 0.28)) { mapState.isVisible = true }
                                } else {
                                    // Clic hors de tout département dessiné : désélectionne,
                                    // sans fermer l'inspecteur (il affiche un message à la
                                    // place, voir InspectorPanelView).
                                    selectedDepartementName = nil
                                    mapState.title = ""
                                }
                            }
                        )
                }
                .ignoresSafeArea(edges: [.horizontal, .bottom])

                // Colonne à largeur fixe, hauteur naturelle plafonnée à
                // l'espace disponible (sans mesure ni `ViewThatFits` — ce
                // dernier mesure mal les vues contenant un `GeometryReader`,
                // comme les réglettes `CriterionRow`, et leur fait perdre
                // leur largeur réelle).
                settingsScrollView(maxHeight: max(0, geo.size.height - columnOuterPadding * 2))
                    .padding(columnOuterPadding)
            }
            .onAppear {
                moveCamera(totalWidth: geo.size.width, animated: false)
                refreshDepartementsOnMap()
                // À chaque sélection de la section, Pays et "Géographie et
                // Culture" sont dépliés. L'accordéon est suspendu le temps
                // d'appliquer ces valeurs (sinon l'ouverture de Géographie
                // replierait Pays aussitôt).
                isApplyingDefaultExpansion = true
                state.bigMacExpandedPays = true
                state.bigMacExpandedRegions = true
                DispatchQueue.main.async { isApplyingDefaultExpansion = false }
            }
            .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: mapState.spanDegrees) { _, newSpan in applyZoom(newSpan) }
            .onChange(of: mapState.recenterTick) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            // Accordéon : Pays se replie dès que "Géographie et Culture"
            // s'ouvre (mais ouvrir Pays ne referme pas l'autre bloc — seul
            // Pays a ce comportement, pour rester l'état "par défaut" au
            // premier bloc).
            .onChange(of: state.bigMacExpandedRegions) { _, isExpanded in if isExpanded && !isApplyingDefaultExpansion { state.bigMacExpandedPays = false } }
            .onChange(of: mapFilters) { _, _ in refreshDepartementsOnMap() }
            .onChange(of: geo.size.width) { _, newValue in moveCamera(totalWidth: newValue, animated: false) }
        }
    }

    /// Colonne scrollable si nécessaire — extraite du `body` pour aider le
    /// type-checker (l'expression combinée dépassait son délai).
    private func settingsScrollView(maxHeight: CGFloat) -> some View {
        ScrollView {
            settingsColumn
        }
        .frame(width: columnWidth)
        .frame(maxHeight: maxHeight, alignment: .top)
    }

    // MARK: Contenu carte (départements des communes filtrées, ou pin pays)

    /// Extrait en `@MapContentBuilder` séparé — le corps de `Map` avec les
    /// deux branches (rings région simple vs. groupes de départements)
    /// inline dépassait le temps de type-check du compilateur.
    @MapContentBuilder
    private var mapContent: some MapContent {
        if mapState.departementNames.isEmpty {
            Marker(mapState.title, coordinate: mapState.coordinate)
        } else {
            ForEach(mapState.departementNames, id: \.self) { name in
                departementRings(DepartementBoundaries.rings[name] ?? [], isHovered: name == hoveredDepartementName, isSelected: name == selectedDepartementName)
            }
        }
    }

    @MapContentBuilder
    private func departementRings(_ rings: [[CLLocationCoordinate2D]], isHovered: Bool, isSelected: Bool) -> some MapContent {
        let opacity = 0.05 + (isSelected ? 0.05 : 0) + (isHovered ? 0.07 : 0)
        let trace = ClassicTheme.accent.mapTrace(dark: colorScheme == .dark)
        ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
            MapPolygon(coordinates: ring)
                .foregroundStyle(trace.opacity(opacity))
                .stroke(trace, lineWidth: 2)
        }
    }

    /// Département tracé sous le point écran `point` (hit-test manuel, voir
    /// `DepartementBoundaries.departement(at:among:)`).
    private func departementName(at point: CGPoint, proxy: MapProxy) -> String? {
        guard let coordinate = proxy.convert(point, from: .local) else { return nil }
        return DepartementBoundaries.departement(at: coordinate, among: mapState.departementNames)
    }

    // MARK: Départements correspondant aux communes filtrées + Culture

    /// Réglages dont dépend la liste des départements tracés — un seul
    /// `onChange` pour tous.
    private struct MapFilters: Equatable {
        let excludeOverseas: Bool
        let excludeCorse: Bool
        let geo2: [Int]
        let communeSizes: Set<CommuneSizeCategory>
        let culture: [Int]
    }

    private var mapFilters: MapFilters {
        MapFilters(excludeOverseas: state.excludeOverseas, excludeCorse: state.excludeCorse, geo2: state.geo2, communeSizes: state.communeSizes, culture: state.culture)
    }

    /// Départements correspondant aux tailles de commune cochées (codes
    /// précalculés côté `CommuneSizeData`), classés par pertinence en
    /// combinant les réglages de proximité (`state.geo2`) et les poids
    /// Culture (moyenne des deux scores 0-100). Tous les départements
    /// correspondants sont montrés, sans plafond.
    private var matchingDepartementNames: [String] {
        let weights = state.culture
        let matchingCodes = CommuneSizeData.matchingDepartementCodes(state.communeSizes)
        // Un critère Culture à "déterminant" (poids 2) devient lui
        // aussi une condition ET, au même titre que Mer/Pays étranger côté
        // proximité (voir `ClassicState.rankedDepartements`) — sinon Festivals
        // à "déterminant" ne fait que réordonner les départements qui ont
        // déjà passé les filtres de proximité, sans jamais en écarter aucun.
        // Même tolérance progressive qu'en proximité (voir
        // `FranceGeoData.allowedMisses`), comptée sur les seuls critères
        // Culture : les 3 exigés à la fois ne laissaient que 3 départements
        // sur 101, alors que le Rhône ou les Bouches-du-Rhône n'en ratent
        // qu'un seul.
        let allowedCultureMisses = FranceGeoData.allowedMisses(activeFilterCount: weights.filter { $0 > 0 }.count)
        return state.rankedDepartements()
            .filter { matchingCodes.contains($0.dep.codeInsee) }
            .filter { entry in
                let misses = zip(CultureScores.criterionKeys, weights).filter {
                    !CultureScores.passesHardFilter(forDepartementCode: entry.dep.codeInsee, key: $0.0, weight: $0.1, maxWeight: ClassicState.maxWeight)
                }.count
                return misses <= allowedCultureMisses
            }
            .map { entry -> (name: String, score: Double) in
                let cultureScore = CultureScores.weightedScore(forDepartementCode: entry.dep.codeInsee, weights: weights)
                return (entry.dep.nom, (entry.score + cultureScore) / 2)
            }
            .sorted { $0.score > $1.score }
            .map(\.name)
    }

    /// Redessine les périmètres des départements correspondants — appelé à
    /// l'apparition et à chaque changement de taille de commune, de réglage
    /// de proximité ou de poids Culture, sans déplacer la caméra.
    private func refreshDepartementsOnMap() {
        let names = matchingDepartementNames
        mapState.departementNames = names
        // Si le département sélectionné disparaît du nouvel ensemble (les
        // filtres ont changé), on désélectionne plutôt que de garder
        // l'inspecteur sur un département qui n'est plus affiché.
        if let selected = selectedDepartementName, !names.contains(selected) {
            selectedDepartementName = nil
            mapState.title = ""
        }
    }

    // MARK: Colonne

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            paysBlock
            regionsBlock
        }
        .padding(columnInnerPadding)
    }

    // MARK: Bloc 1 — Pays

    private var paysBlock: some View {
        blockDisclosure(title: "Pays", isExpanded: $state.bigMacExpandedPays, enabled: true) {
            PaysCountryBlock(ink: c.ink)
        }
    }

    // MARK: Bloc 2 — Régions + tailles de commune + Culture

    private var regionsBlock: some View {
        // Réservé à la France (données départementales) : pour tout autre pays
        // le bloc est replié et ne peut pas être déplié.
        blockDisclosure(title: "Géographie et Culture", isExpanded: $state.bigMacExpandedRegions, enabled: state.country == "France") {
            VStack(alignment: .leading, spacing: 14) {
                // Les deux bascules d'exclusion (Territoires ultramarins / Corse).
                VStack(alignment: .leading, spacing: 8) {
                    SelecteurCheckbox(label: "Exclure les Territoires ultramarins", isOn: $state.excludeOverseas, ink: c.body)
                    SelecteurCheckbox(label: "Exclure la Corse", isOn: $state.excludeCorse, ink: c.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Communes", color: c.faint, font: CFont.rounded(13, weight: .medium))
                    ForEach(CommuneSizeCategory.allCases) { category in
                        HStack(spacing: 8) {
                            SelecteurCheckbox(label: category.rawValue, isOn: communeSizeBinding(category), ink: c.body)
                            Spacer(minLength: 0)
                            InfoPopoverButton(text: category.description, tint: c.faint)
                        }
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Proximités") { state.resetGeo2() }
                    ForEach(state.geo2Rows) { row in
                        CriterionRow(row: row, thumbSize: 14.4) { state.setGeo2(row.id, value: $0) }
                            .padding(.trailing, 8)
                    }
                }
                .padding(.top, 12)

                // Réglages Culture, après Proximités.
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Culture") { state.resetCulture() }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.cultureRows) { row in
                            CriterionRow(row: row) { state.setCulture(row.id, value: $0) }
                                .padding(.vertical, 4)
                                .padding(.trailing, 8)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 6)
            }
        }
    }

    private func communeSizeBinding(_ category: CommuneSizeCategory) -> Binding<Bool> {
        Binding(
            get: { state.communeSizes.contains(category) },
            set: { if $0 { state.communeSizes.insert(category) } else { state.communeSizes.remove(category) } }
        )
    }

    /// En-tête de section (Proximités, Culture) avec son bouton
    /// « RÉINITIALISER » en pastille.
    private func sectionHeader(_ title: String, reset: @escaping () -> Void) -> some View {
        HStack(alignment: .center) {
            Eyebrow(title, color: c.faint, font: CFont.rounded(13, weight: .medium))
            Spacer()
            Button(action: reset) {
                Text("Réinitialiser")
                    .font(CFont.rounded(10, weight: .medium))
                    .foregroundStyle(c.faint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(c.faint.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Disclosure commun

    /// `DisclosureGroup` stylé pour matcher les panneaux flottants existants
    /// (matériau translucide de la colonne, typographie `Eyebrow`/`CFont`) —
    /// première utilisation de `DisclosureGroup` dans ce module.
    private func blockDisclosure<Content: View>(title: String, isExpanded: Binding<Bool>, enabled: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        // Anime explicitement le dépli/repli : `DisclosureGroup` change son
        // binding directement au clic sur le chevron, sans passer par
        // `withAnimation`, ce qui donnait un repli/dépli instantané et sec.
        let animatedExpanded = Binding<Bool>(
            get: { isExpanded.wrappedValue },
            set: { newValue in withAnimation(.easeInOut(duration: 0.3)) { isExpanded.wrappedValue = newValue } }
        )
        return VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: enabled ? animatedExpanded : .constant(false)) {
                content()
                    .padding(.top, 10)
                    .padding(.leading, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } label: {
                // Toute la largeur du titre déplie/replie le bloc, pas
                // seulement le chevron (`DisclosureGroup` ne rend cliquable
                // que ce dernier sur macOS).
                HStack(spacing: 0) {
                    Text(title.uppercased())
                        .font(CFont.rounded(14, weight: .bold))
                        .foregroundStyle(enabled && isExpanded.wrappedValue ? c.ink : c.faint)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if enabled { animatedExpanded.wrappedValue.toggle() }
                }
            }
            .tint(c.faint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 10).fill(blockFill)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(blockStroke, lineWidth: 1))
    }

    // MARK: Caméra

    /// Applique un changement de `spanDegrees` (boutons de zoom de la
    /// toolbar) à la caméra courante — la molette/le trackpad modifient déjà
    /// `position` directement via MapKit, mais les boutons ne passent que
    /// par `mapState.spanDegrees`, qu'il faut donc écouter.
    private func applyZoom(_ newSpan: Double) {
        guard let current = lastRegion else { return }
        let updated = MKCoordinateRegion(
            center: current.center,
            span: MKCoordinateSpan(latitudeDelta: newSpan, longitudeDelta: newSpan)
        )
        withAnimation(.easeInOut(duration: 0.25)) { position = .region(updated) }
        lastRegion = updated
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
