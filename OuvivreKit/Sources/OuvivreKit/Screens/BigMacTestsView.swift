import SwiftUI
import MapKit

/// "Big Mac" (nom provisoire) — même présentation plein cadre que Géographie 2
/// (fond MapKit + colonne flottante translucide), mais la colonne empile 4
/// blocs rétractables (`DisclosureGroup`) qui reprennent, dans l'ordre,
/// Pays → Régions (+ tailles de commune) → Culture. Chaque bloc
/// hérite de l'état partagé `ClassicState`, donc les choix persistent d'un
/// bloc à l'autre ; les blocs sont indépendants (pas d'entonnoir) : chaque réglage
/// met à jour la carte en direct.
public struct BigMacTestsView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    @EnvironmentObject var mapState: MapPanelState
    @Environment(\.colorScheme) private var colorScheme
    let derived: ClassicDerived

    private var columnInk: Color { colorScheme == .dark ? Color(hex: 0xF4F2EE) : ClassicTheme.ink }
    private var columnBody: Color { colorScheme == .dark ? Color(hex: 0xD9D4C9) : ClassicTheme.body }
    private var columnFaint: Color { colorScheme == .dark ? Color(hex: 0xA39D91) : ClassicTheme.faint }

    @State private var position: MapCameraPosition = .automatic
    @State private var lastRegion: MKCoordinateRegion?
    @State private var transitionGeneration = 0
    /// Département actuellement survolé — rend son polygone opaque, comme
    /// dans Régions (`hoveredDepartementName` de `GeoView2`). MapKit ne
    /// propose pas de survol par forme, donc on hit-teste manuellement le
    /// point de la souris contre les polygones via `MapReader`.
    @State private var hoveredDepartementName: String?
    /// Département cliqué, dont le polygone reste opaque tant qu'on ne
    /// clique pas ailleurs (contrairement au survol, transitoire).
    @State private var selectedDepartementName: String?

    // L'ouverture/fermeture des blocs vit dans `ClassicState` (pas un
    // `@State` local) pour rester persistante en quittant puis en revenant
    // sur cet écran — sinon `BigMacTestsView` est recréée à chaque fois et tout
    // se replie.

    // Liste des communes correspondantes (bloc Régions) : les 30 premières
    // s'affichent directement, le reste se déplie — même pattern que
    // `showMoreDepartements` dans GeoView2.
    @State private var showMoreCommunes = false
    /// Vrai pendant l'application du dépli par défaut à l'apparition.
    @State private var isApplyingDefaultExpansion = false

    private let columnWidth: CGFloat = 420
    private let columnOuterPadding: CGFloat = 20
    private let columnInnerPadding: CGFloat = 16
    private let topCommunesCount = 30
    private let moreCommunesMaxHeight: CGFloat = 440
    /// Nombre de départements affichés sur la carte — sans ce plafond, tous
    /// les départements correspondant aux tailles de commune restent
    /// affichés quel que soit leur classement, et les réglages de
    /// proximité/Culture (qui ne font que réordonner la liste) n'ont donc
    /// aucun effet visible (même bug que "0 communes" : effet invisible
    /// plutôt qu'absent). Même convention que `topDepartementsCount` dans
    /// GeoView2.
    private let topDepartementsCount = 25

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
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
                                    withAnimation(.easeInOut(duration: 0.28)) { mapState.bigMacInspectorVisible = true }
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
            // Accordéon : Pays se replie dès qu'un autre bloc s'ouvre (mais
            // ouvrir Pays ne referme pas les autres — seul Pays a ce
            // comportement, pour rester l'état "par défaut" au premier bloc).
            .onChange(of: state.bigMacExpandedRegions) { _, isExpanded in if isExpanded && !isApplyingDefaultExpansion { state.bigMacExpandedPays = false } }
            .onChange(of: state.bigMacExpandedCulture) { _, isExpanded in if isExpanded && !isApplyingDefaultExpansion { state.bigMacExpandedPays = false } }
            .onChange(of: state.excludeOverseas) { _, _ in refreshDepartementsOnMap() }
            .onChange(of: state.excludeCorse) { _, _ in refreshDepartementsOnMap() }
            .onChange(of: state.geo2) { _, _ in refreshDepartementsOnMap() }
            .onChange(of: state.includeVillage) { _, _ in refreshDepartementsOnMap() }
            .onChange(of: state.includePetiteVille) { _, _ in refreshDepartementsOnMap() }
            .onChange(of: state.includeVilleMoyenne) { _, _ in refreshDepartementsOnMap() }
            .onChange(of: state.includeGrandeVille) { _, _ in refreshDepartementsOnMap() }
            .onChange(of: state.groups) { _, _ in refreshDepartementsOnMap() }
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
        if mapState.departementRingGroups.isEmpty {
            ForEach(Array(mapState.regionRings.enumerated()), id: \.offset) { _, ring in
                MapPolygon(coordinates: ring)
                    .foregroundStyle(theme.accent.opacity(0.16))
                    .stroke(theme.accent, lineWidth: 2)
            }
            if mapState.regionRings.isEmpty {
                Marker(mapState.title, coordinate: mapState.coordinate)
            }
        } else {
            ForEach(mapState.departementRingGroups, id: \.name) { group in
                departementRings(group.rings, isHovered: group.name == hoveredDepartementName, isSelected: group.name == selectedDepartementName)
            }
        }
    }

    @MapContentBuilder
    private func departementRings(_ rings: [[CLLocationCoordinate2D]], isHovered: Bool, isSelected: Bool) -> some MapContent {
        ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
            MapPolygon(coordinates: ring)
                .foregroundStyle(theme.accent.opacity(isHovered ? 0.54 : (isSelected ? 0.54 * 0.85 : 0.16)))
                .stroke(theme.accent, lineWidth: 2)
        }
    }

    /// Hit-test manuel : convertit un point écran en coordonnée puis
    /// cherche le premier département dont un des anneaux le contient
    /// (ray casting) — MapKit ne propose pas de survol/tap par forme sur
    /// `MapPolygon`.
    private func departementName(at point: CGPoint, proxy: MapProxy) -> String? {
        guard let coordinate = proxy.convert(point, from: .local) else { return nil }
        for group in mapState.departementRingGroups {
            if group.rings.contains(where: { Self.ring($0, contains: coordinate) }) {
                return group.name
            }
        }
        return nil
    }

    /// Ray casting standard (pair/impair) sur un anneau de coordonnées.
    private static func ring(_ ring: [CLLocationCoordinate2D], contains coordinate: CLLocationCoordinate2D) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let pi = ring[i], pj = ring[j]
            if (pi.latitude > coordinate.latitude) != (pj.latitude > coordinate.latitude) {
                let slope = (pj.longitude - pi.longitude) / (pj.latitude - pi.latitude)
                let longitudeAtLatitude = pi.longitude + slope * (coordinate.latitude - pi.latitude)
                if coordinate.longitude < longitudeAtLatitude { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    // MARK: Départements correspondant aux communes filtrées + Culture

    /// Codes département des communes qui correspondent aux tailles cochées
    /// — précalculé côté `CommuneSizeData` (groupes par catégorie), évite de
    /// refiltrer/trier ~35k communes à chaque changement d'état.
    private var matchingDepartementCodes: Set<String> {
        CommuneSizeData.matchingDepartementCodes(
            includeVillage: state.includeVillage,
            includePetiteVille: state.includePetiteVille,
            includeVilleMoyenne: state.includeVilleMoyenne,
            includeGrandeVille: state.includeGrandeVille
        )
    }

    /// Poids Culture (Musées, Lieux du patrimoine, Festivals) actuellement
    /// réglés, dans l'ordre de `CultureScores.criterionKeys`.
    private var cultureWeights: [Int] {
        cultureRows.map(\.row.value)
    }

    /// Tant qu'aucun critère (proximité ou Culture) n'est réglé, tous les
    /// scores retombent à 50/100 pour chaque département : un "top 10" y
    /// serait arbitraire (ordre de tri stable, sans rapport avec un critère
    /// visible) et donnerait l'impression trompeuse d'un classement. Dans ce
    /// cas, on affiche tous les départements correspondants, sans plafond.
    private var hasActiveRankingCriterion: Bool {
        state.geo2.contains { $0 > 0 } || cultureWeights.contains { $0 > 0 }
    }

    /// Ces départements, classés par pertinence en combinant les réglages de
    /// proximité (`state.geo2`) et les poids Culture (moyenne des deux
    /// scores 0-100) — filtrés à l'ensemble issu des tailles de commune, et
    /// plafonnés aux 10 mieux classés seulement si un critère est réglé.
    private var matchingDepartementNames: [String] {
        let weights = cultureWeights
        // Un critère Culture à "déterminant" (poids 3) devient lui
        // aussi une condition ET, au même titre que Mer/Pays étranger côté
        // proximité (voir `rankedDepartements(maxWeight:)`) — sinon Festivals
        // à "déterminant" ne fait que réordonner les départements qui ont
        // déjà passé les filtres de proximité, sans jamais en écarter aucun.
        let ranked = derived.rankedDepartements(weights: state.geo2, maxWeight: 2)
            .filter { matchingDepartementCodes.contains($0.dep.codeInsee) }
            .filter { entry in
                CultureScores.criterionKeys.enumerated().allSatisfy { i, key in
                    i >= weights.count || CultureScores.passesHardFilter(forDepartementCode: entry.dep.codeInsee, key: key, weight: weights[i], maxWeight: 2)
                }
            }
            .map { entry -> (name: String, score: Double) in
                let cultureScore = CultureScores.weightedScore(forDepartementCode: entry.dep.codeInsee, weights: weights)
                return (entry.dep.nom, (entry.score + cultureScore) / 2)
            }
            .sorted { $0.score > $1.score }
        // Plafond top-25 temporairement désactivé pour tester l'affichage
        // sans limite — tous les départements correspondants sont montrés,
        // classés par pertinence.
        return ranked.map(\.name)
    }

    /// Redessine les périmètres des départements correspondants — appelé à
    /// l'apparition et à chaque changement de taille de commune, de réglage
    /// de proximité ou de poids Culture (comme `refreshTopDepartementsOnMap`
    /// dans GeoView2), sans déplacer la caméra.
    private func refreshDepartementsOnMap() {
        let names = matchingDepartementNames
        mapState.updateDepartementRingGroups(names)
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
            if isCultureBlockVisible {
                cultureBlock
            }
        }
        .padding(columnInnerPadding)
    }

    // MARK: Bloc 1 — Pays

    private var paysBlock: some View {
        blockDisclosure(title: "Pays", bold: true, isExpanded: $state.bigMacExpandedPays, enabled: true) {
            PaysCountryBlock(derived: derived, ink: columnInk, faint: columnFaint, showFacts: false, countryFont: CFont.rounded(13))
        }
    }

    // MARK: Bloc 2 — Régions + tailles de commune

    private var matchingCommunes: [CommuneSizeEntry] {
        CommuneSizeData.matching(
            includeVillage: state.includeVillage,
            includePetiteVille: state.includePetiteVille,
            includeVilleMoyenne: state.includeVilleMoyenne,
            includeGrandeVille: state.includeGrandeVille
        )
    }
    private var communeCount: Int { matchingCommunes.count }
    /// Les 30 premières communes correspondantes, toujours affichées — et
    /// aussi celles utilisées comme pins sur la carte (pour éviter d'en
    /// surcharger l'affichage avec les "autres communes").
    private var shownCommunes: [CommuneSizeEntry] { Array(matchingCommunes.prefix(topCommunesCount)) }
    private var moreCommunes: [CommuneSizeEntry] { Array(matchingCommunes.dropFirst(topCommunesCount)) }

    private var regionsBlock: some View {
        blockDisclosure(title: "Géographie et Culture", bold: true, isExpanded: $state.bigMacExpandedRegions, enabled: true) {
            VStack(alignment: .leading, spacing: 14) {
                RegionExclusionToggles(excludeOverseas: $state.excludeOverseas, excludeCorse: $state.excludeCorse, accent: theme.accent, ink: columnBody, labelFont: CFont.rounded(13))

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("COMMUNES", color: columnFaint, font: CFont.rounded(10))
                    sizeCheckbox("Village", description: CommuneSizeCategory.village.description, isOn: $state.includeVillage)
                    sizeCheckbox("Petite ville", description: CommuneSizeCategory.petiteVille.description, isOn: $state.includePetiteVille)
                    sizeCheckbox("Ville moyenne", description: CommuneSizeCategory.villeMoyenne.description, isOn: $state.includeVilleMoyenne)
                    sizeCheckbox("Grande ville", description: CommuneSizeCategory.grandeVille.description, isOn: $state.includeGrandeVille)
                }
                .padding(.top, 4)

                // La liste des communes (30 premières + "autres" dépliables)
                // est retirée de l'affichage pour l'instant — on la
                // réutilisera plus tard. `communesList`/`communeRow` restent
                // définies ci-dessous ; `shownCommunes` continue d'alimenter
                // les pins sur la carte.

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Eyebrow("PROXIMITÉS", color: columnFaint, font: CFont.rounded(10))
                        Spacer()
                        resetButton { state.resetGeo2() }
                    }

                    ForEach(derived.geo2Rows) { row in
                        CriterionRow(row: row, thumbSize: 14.4, labelFont: CFont.rounded(13), labelColor: columnInk, dotGrowthPerStep: 1.5, tagFont: CFont.rounded(10), tagCase: .capitalized) { state.setGeo2(row.id, value: $0) }
                            .padding(.trailing, 8)
                    }
                }
                .padding(.top, 12)

                // Réglages Culture transférés ici (après Proximités) depuis
                // l'ancien bloc "Culture", désormais masqué.
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Eyebrow("CULTURE", color: columnFaint, font: CFont.rounded(10))
                        Spacer()
                        resetButton {
                            for entry in cultureRows { state.setGroup(cultureGroupIndex, entry.rowIndex, value: 0) }
                        }
                    }
                    cultureRowsContent
                }
                .padding(.top, 12)
                .padding(.bottom, 6)
            }
        }
    }

    /// Bouton « RÉINITIALISER » en pastille, commun aux en-têtes Proximités et Culture.
    private func resetButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Réinitialiser")
                .font(CFont.rounded(10))
                .foregroundStyle(columnFaint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(columnFaint.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Liste des communes correspondant aux filtres — 30 premières en clair,
    /// le reste replié derrière "AUTRES COMMUNES" (même pattern que
    /// `departementsCard` dans GeoView2).
    private var communesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !shownCommunes.isEmpty {
                Eyebrow("COMMUNES", color: columnFaint, font: CFont.rounded(10, weight: .medium))
                    .padding(.bottom, 6)

                VStack(spacing: 0) {
                    ForEach(shownCommunes) { entry in
                        communeRow(entry)
                    }
                }
            }

            if !moreCommunes.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showMoreCommunes.toggle() }
                } label: {
                    HStack {
                        Image(systemName: showMoreCommunes ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(columnFaint)
                        Eyebrow("AUTRES COMMUNES", color: columnFaint, font: CFont.rounded(10, weight: .medium))
                        Spacer()
                    }
                    .padding(.top, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showMoreCommunes {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(moreCommunes) { entry in
                                communeRow(entry)
                            }
                        }
                    }
                    .frame(maxHeight: moreCommunesMaxHeight)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func communeRow(_ entry: CommuneSizeEntry) -> some View {
        Text(entry.name)
            .font(CFont.rounded(14, weight: .medium))
            .foregroundStyle(columnInk)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sizeCheckbox(_ label: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
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
                    Text(label).font(CFont.rounded(13)).foregroundStyle(columnBody)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            InfoPopoverButton(text: description, tint: columnFaint)
        }
    }

    // MARK: Bloc 3 — Culture (Musées, Lieux du patrimoine, Festivals uniquement)

    /// Les 3 lignes de `ClassicStatic.groups` CULTURE conservées pour ce
    /// bloc — sources :
    /// - Musées : https://culture.data.gouv.fr/datasets/61777ddaa9101d073e5506cd
    /// - Lieux du patrimoine : https://culture.data.gouv.fr/datasets/628da9ff836d8bf454c7fd48
    /// - Festivals : https://culture.data.gouv.fr/datasets/62cf95993d99f22480f49334
    /// Mêmes 3 niveaux que "Proximités" (indifférent/important/
    /// déterminant, 0...2) plutôt que l'échelle à 6 niveaux par défaut des
    /// groupes — `WeightedRow` est reconstruite avec `maxValue`/`tags`
    /// substitués, la valeur brute de `state.groups` étant déjà clampée à 2
    /// par `setGroup` côté écriture (voir `cultureBlock`).
    private var cultureRows: [(rowIndex: Int, row: WeightedRow)] {
        guard let cultureGroup = derived.groups.first(where: { $0.title == "CULTURE" }) else { return [] }
        let keep: Set<String> = ["Musées", "Lieux du patrimoine", "Festivals"]
        return cultureGroup.rows.enumerated()
            .filter { keep.contains($0.element.label) }
            .map { offset, row in
                (rowIndex: offset, row: WeightedRow(id: row.id, label: row.label, value: min(row.value, 2), maxValue: 2, tags: ClassicStatic.tagsGeo2))
            }
    }
    private var cultureGroupIndex: Int {
        ClassicStatic.groups.firstIndex { $0.title == "CULTURE" } ?? 0
    }

    /// Les 3 réglettes Culture — affichées dans le bloc "Géographie et
    /// Culture" (après Proximités). Les réglages restent actifs (ils
    /// pilotent toujours le classement des départements) ; seul l'ancien
    /// bloc "Culture" séparé est masqué (`isCultureBlockVisible`).
    private var cultureRowsContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(cultureRows, id: \.rowIndex) { entry in
                CriterionRow(row: entry.row, thumbSize: 16, trackHeight: 4, labelFont: CFont.rounded(13), labelColor: columnInk, dotGrowthPerStep: 1.5, tagFont: CFont.rounded(10), tagCase: .capitalized) {
                    state.setGroup(cultureGroupIndex, entry.rowIndex, value: min($0, 2))
                }
                .padding(.vertical, 4)
                .padding(.trailing, 8)
            }
        }
    }

    /// Ancien bloc "Culture" séparé : masqué (son contenu vit désormais
    /// dans "Géographie et Culture"). Repasser à `true` pour le réafficher.
    private let isCultureBlockVisible = false

    private var cultureBlock: some View {
        blockDisclosure(title: "Culture", isExpanded: $state.bigMacExpandedCulture, enabled: true) {
            cultureRowsContent
        }
    }

    // MARK: Disclosure commun

    /// `DisclosureGroup` stylé pour matcher les panneaux flottants existants
    /// (matériau translucide de la colonne, typographie `Eyebrow`/`CFont`) —
    /// première utilisation de `DisclosureGroup` dans ce module.
    @ViewBuilder
    private func blockDisclosure<Content: View>(title: String, bold: Bool = false, isExpanded: Binding<Bool>, enabled: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
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
                        .font(CFont.rounded(11, weight: bold ? .bold : .semibold))
                        .foregroundStyle(enabled && isExpanded.wrappedValue ? columnInk : columnFaint)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if enabled { animatedExpanded.wrappedValue.toggle() }
                }
            }
            .tint(columnFaint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(ClassicTheme.sidebarBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ClassicTheme.border.opacity(0.6), lineWidth: 1))
    }

    // MARK: Caméra (identique à PaysView/GeoView2)

    /// Applique un changement de `spanDegrees` (boutons de zoom de la
    /// toolbar) à la caméra courante — la molette/le trackpad modifient déjà
    /// `position` directement via MapKit, mais les boutons ne passent que
    /// par `mapState.spanDegrees`, qu'il faut donc écouter (comme
    /// `applyZoom` dans GeoView2).
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

/// Petit bouton `info.circle` qui affiche une description au clic, via
/// `.popover` — utilisé par les 4 cases à cocher "taille de commune" du
/// bloc Régions.
private struct InfoPopoverButton: View {
    let text: String
    let tint: Color
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text)
                .font(CFont.rounded(12))
                .foregroundStyle(ClassicTheme.body)
                .padding(12)
                .frame(width: 240, alignment: .leading)
        }
    }
}
