import SwiftUI
import MapKit

/// "Big Mac" (nom provisoire) — même présentation plein cadre que Géographie 2
/// (fond MapKit + colonne flottante translucide), mais la colonne empile 4
/// blocs rétractables (`DisclosureGroup`) qui reprennent, dans l'ordre,
/// Pays → Régions (+ tailles de commune) → Culture → Mobilité. Chaque bloc
/// hérite de l'état partagé `ClassicState`, donc les choix persistent d'un
/// bloc à l'autre ; un bloc reste désactivé tant que le précédent n'a pas au
/// moins une sélection active (léger effet de dépendance, sans graphe complexe).
public struct BigMacView: View {
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
    @State private var columnContentHeight: CGFloat = 0

    // Un seul bloc ouvert par défaut : "Pays".
    @State private var expandedPays = true
    @State private var expandedRegions = false
    @State private var expandedCulture = false
    @State private var expandedMobilite = false

    // Liste des communes correspondantes (bloc Régions) : les 30 premières
    // s'affichent directement, le reste se déplie — même pattern que
    // `showMoreDepartements` dans GeoView2.
    @State private var showMoreCommunes = false

    private let columnWidth: CGFloat = 340
    private let columnOuterPadding: CGFloat = 20
    private let columnInnerPadding: CGFloat = 16
    private let topCommunesCount = 30
    private let moreCommunesMaxHeight: CGFloat = 440

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Map(position: $position) {
                    Marker(mapState.title, coordinate: mapState.coordinate)
                    ForEach(shownCommunes) { entry in
                        Marker(entry.name, coordinate: entry.coordinate)
                    }
                }
                .mapStyle(mapState.planType.style(elevation: .automatic))
                .onMapCameraChange { context in lastRegion = context.region }
                .ignoresSafeArea(edges: [.horizontal, .bottom])

                let maxColumnHeight = geo.size.height - columnOuterPadding * 2
                ScrollView {
                    settingsColumn
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear.preference(key: ColumnHeightPreferenceKey.self, value: contentGeo.size.height)
                            }
                        )
                }
                .onPreferenceChange(ColumnHeightPreferenceKey.self) { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) { columnContentHeight = newValue }
                }
                .frame(width: columnWidth, height: min(columnContentHeight, maxColumnHeight))
                .padding(columnOuterPadding)
            }
            .onAppear { moveCamera(totalWidth: geo.size.width, animated: false) }
            .onChange(of: mapState.coordinate.latitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: mapState.coordinate.longitude) { _, _ in moveCamera(totalWidth: geo.size.width, animated: true) }
            .onChange(of: state.excludeOverseas) { _, _ in }
            .onChange(of: geo.size.width) { _, newValue in moveCamera(totalWidth: newValue, animated: false) }
        }
    }

    // MARK: Dépendances légères entre blocs

    /// Bloc 1 "actif" dès qu'un pays est choisi — c'est toujours le cas
    /// (un pays par défaut existe), donc Régions est utilisable d'emblée.
    private var paysHasSelection: Bool { !state.country.isEmpty }
    /// Bloc 2 "actif" dès qu'au moins une taille de commune est cochée.
    private var regionsHasSelection: Bool {
        state.includeVillage || state.includePetiteVille || state.includeVilleMoyenne || state.includeGrandeVille
    }
    /// Bloc 3 "actif" dès qu'un des 3 critères culture retenus a un poids > 0.
    private var cultureHasSelection: Bool {
        cultureRows.contains { $0.row.value > 0 }
    }

    // MARK: Colonne

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            paysBlock
            regionsBlock
            cultureBlock
            mobiliteBlock
        }
        .padding(columnInnerPadding)
        .background(.regularMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    // MARK: Bloc 1 — Pays

    private var paysBlock: some View {
        blockDisclosure(title: "Pays", isExpanded: $expandedPays, enabled: true) {
            PaysCountryBlock(derived: derived, ink: columnInk, faint: columnFaint)
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
        blockDisclosure(title: "Régions", isExpanded: $expandedRegions, enabled: paysHasSelection) {
            VStack(alignment: .leading, spacing: 14) {
                RegionExclusionToggles(excludeOverseas: $state.excludeOverseas, excludeCorse: $state.excludeCorse, accent: theme.accent, ink: columnBody)

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("TAILLE DE COMMUNE", color: columnFaint)
                    sizeCheckbox("Village", description: CommuneSizeCategory.village.description, isOn: $state.includeVillage)
                    sizeCheckbox("Petite ville", description: CommuneSizeCategory.petiteVille.description, isOn: $state.includePetiteVille)
                    sizeCheckbox("Ville moyenne", description: CommuneSizeCategory.villeMoyenne.description, isOn: $state.includeVilleMoyenne)
                    sizeCheckbox("Grande ville", description: CommuneSizeCategory.grandeVille.description, isOn: $state.includeGrandeVille)
                }
                .padding(.top, 4)

                Text("\(communeCount) communes correspondantes")
                    .font(CFont.mono(11, weight: .medium))
                    .foregroundStyle(columnFaint)

                communesList

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow("PROXIMITÉS", color: columnFaint)
                        Spacer()
                        Button {
                            state.resetGeo2()
                        } label: {
                            Text("Réinitialiser")
                                .font(.system(size: 13))
                                .foregroundStyle(columnFaint)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(derived.geo2Rows) { row in
                        CriterionRow(row: row, labelColor: columnInk) { state.setGeo2(row.id, value: $0) }
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    /// Liste des communes correspondant aux filtres — 30 premières en clair,
    /// le reste replié derrière "AUTRES COMMUNES" (même pattern que
    /// `departementsCard` dans GeoView2).
    private var communesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !shownCommunes.isEmpty {
                Eyebrow("COMMUNES", color: columnFaint)
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
                        Eyebrow("AUTRES COMMUNES", color: columnFaint)
                        Spacer()
                        Image(systemName: showMoreCommunes ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(columnFaint)
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
            .font(CFont.sans(14, weight: .medium))
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
                    Text(label).font(CFont.sans(13)).foregroundStyle(columnBody)
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
    private var cultureRows: [(rowIndex: Int, row: WeightedRow)] {
        guard let cultureGroup = derived.groups.first(where: { $0.title == "CULTURE" }) else { return [] }
        let keep: Set<String> = ["Musées", "Lieux du patrimoine", "Festivals"]
        return cultureGroup.rows.enumerated()
            .filter { keep.contains($0.element.label) }
            .map { (rowIndex: $0.offset, row: $0.element) }
    }
    private var cultureGroupIndex: Int {
        ClassicStatic.groups.firstIndex { $0.title == "CULTURE" } ?? 0
    }

    private var cultureBlock: some View {
        blockDisclosure(title: "Culture", isExpanded: $expandedCulture, enabled: regionsHasSelection) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(cultureRows, id: \.rowIndex) { entry in
                    CriterionRow(row: entry.row, thumbSize: 12, trackHeight: 3, labelFont: CFont.sans(13), labelColor: columnInk) {
                        state.setGroup(cultureGroupIndex, entry.rowIndex, value: $0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: Bloc 4 — Mobilité (Bus, Pistes cyclables, Gares, Aéroports — inchangé)

    private var mobiliteGroupIndex: Int {
        ClassicStatic.groups.firstIndex { $0.title == "MOBILITÉ" } ?? 0
    }
    private var mobiliteRows: [WeightedRow] {
        derived.groups.first { $0.title == "MOBILITÉ" }?.rows ?? []
    }

    private var mobiliteBlock: some View {
        blockDisclosure(title: "Mobilité", isExpanded: $expandedMobilite, enabled: cultureHasSelection) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(mobiliteRows) { row in
                    CriterionRow(row: row, thumbSize: 12, trackHeight: 3, labelFont: CFont.sans(13), labelColor: columnInk) {
                        state.setGroup(mobiliteGroupIndex, row.id, value: $0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: Disclosure commun

    /// `DisclosureGroup` stylé pour matcher les panneaux flottants existants
    /// (matériau translucide de la colonne, typographie `Eyebrow`/`CFont`) —
    /// première utilisation de `DisclosureGroup` dans ce module.
    @ViewBuilder
    private func blockDisclosure<Content: View>(title: String, isExpanded: Binding<Bool>, enabled: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: enabled ? isExpanded : .constant(false)) {
                content()
                    .padding(.top, 10)
                    .padding(.leading, 2)
            } label: {
                Text(title.uppercased())
                    .font(CFont.mono(11, weight: .semibold))
                    .foregroundStyle(enabled ? columnInk : columnFaint)
            }
            .disabled(!enabled)
            .tint(columnFaint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(ClassicTheme.background.opacity(colorScheme == .dark ? 0.06 : 0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ClassicTheme.border.opacity(0.6), lineWidth: 1))
        .opacity(enabled ? 1 : 0.55)
    }

    // MARK: Caméra (identique à PaysView/GeoView2)

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

/// Mesure la hauteur naturelle de la colonne de réglages, pour que son
/// conteneur s'étende quand des blocs dépliés dépassent sa hauteur
/// actuelle (jusqu'à la hauteur disponible, au-delà de quoi le `ScrollView`
/// prend le relais).
private struct ColumnHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
                .font(CFont.sans(12))
                .foregroundStyle(ClassicTheme.body)
                .padding(12)
                .frame(width: 240, alignment: .leading)
        }
    }
}
