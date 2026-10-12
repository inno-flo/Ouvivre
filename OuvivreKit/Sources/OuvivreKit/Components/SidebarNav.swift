import SwiftUI

/// The native sidebar list: "Sélecteur" (steps) + "Outils" sections, plus a
/// "Sources" row — selection and highlighting are driven by `List`. Les
/// lignes icône + titre sont des `Label` natifs sans taille forcée : dans une
/// liste `.sidebar` ils prennent les valeurs du système (police système ≈ 13 pt,
/// icône à la taille de sidebar choisie dans Réglages Système > Apparence,
/// emplacement d'icône et alignement vertical gérés par SwiftUI). Seul l'en-tête
/// de section « Favoris » garde un corps fixe (11 pt), plus petit que les titres.
struct SidebarNav: View {
    let selection: Binding<SidebarDestination?>
    @EnvironmentObject private var state: ClassicState
    @Environment(\.openWindow) private var openWindow
    @State private var favoritesExpanded = true
    /// Abscisse de l'icône de Sélecteur, mesurée : Sources (hors de la liste) s'y aligne.
    @State private var iconLeading: CGFloat?

    /// Colonne de droite commune au chevron de l'en-tête et au compteur de
    /// « Tous » : leur centre tombe sur celui du bouton de fermeture de la sidebar
    /// (≈ 25 pt du bord droit, contre ≈ 10 pt de marge intérieure des lignes).
    private static let trailingColumnWidth: CGFloat = 30

    private var isTous: Bool { state.screen == .favoris && state.selectedDepartementCode == nil }

    /// Départements favoris, badge `checkmark.seal.fill` en tête, puis ordre alphabétique — la liste suit
    /// `favoriteDepartementCodes` (ajout/retrait depuis n'importe où).
    private func favoriteDepartements(topCodes: Set<String>) -> [FranceGeoData.DepartementScore] {
        FranceGeoData.departements
            .filter { state.favoriteDepartementCodes.contains($0.codeInsee) }
            .sorted {
                let a = topCodes.contains($0.codeInsee), b = topCodes.contains($1.codeInsee)
                return a != b ? a : $0.nom.localizedStandardCompare($1.nom) == .orderedAscending
            }
    }

    /// Ligne icône + titre : `Label` natif, sans taille ni cadre forcés — le
    /// système fixe police, taille d'icône et alignement vertical. Seule la
    /// graisse du titre varie (gras quand la ligne est sélectionnée).
    @ViewBuilder
    private static func rowLabel(_ title: String, systemImage: String, bold: Bool, badge: Bool = false) -> some View {
        Label {
            Text(title).fontWeight(bold ? .bold : .regular)
        } icon: {
            if badge { Image(systemName: systemImage).modifier(ActiveBadgeStyle()) } else { Image(systemName: systemImage) }
        }
    }

    var body: some View {
        let topCodes = FavorisView.topDepartementCodes(among: state.favoriteDepartementCodes)
        List(selection: selection) {
            // Sélecteur : en tête de la sidebar, sans en-tête de section.
            HStack(spacing: 0) {
                Self.rowLabel("Sélecteur de départements", systemImage: "list.bullet.clipboard.fill",
                              bold: state.screen == .selecteur && state.selectedDepartementCode == nil)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: IconLeadingKey.self, value: proxy.frame(in: .named("sidebar")).minX)
                    })
                Spacer(minLength: 4)
            }
            .tag(SidebarDestination.screen(.selecteur))

            if !state.favoriteDepartementCodes.isEmpty {
                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { favoritesExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Favoris").font(.system(size: 11, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: favoritesExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: Self.trailingColumnWidth)
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if favoritesExpanded {
                        // Titre et compteur partagent la même police (celle du système,
                        // gras quand la rubrique est sélectionnée).
                        HStack(spacing: 0) {
                            Self.rowLabel("Tous les départements", systemImage: "star.fill", bold: isTous, badge: true)
                            Spacer(minLength: 4)
                            Text("\(state.favoriteDepartementCodes.count)")
                                .fontWeight(isTous ? .bold : .regular)
                                .opacity(0.5)
                                .frame(width: Self.trailingColumnWidth)
                        }
                        .tag(SidebarDestination.screen(.favoris))
                        ForEach(favoriteDepartements(topCodes: topCodes), id: \.codeInsee) { dep in
                            let isTop = topCodes.contains(dep.codeInsee)
                            HStack(spacing: 0) {
                                Self.rowLabel(dep.nom, systemImage: isTop ? "checkmark.seal.fill" : "mappin",
                                              bold: state.selectedDepartementCode == dep.codeInsee, badge: isTop)
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture(count: 2).onEnded { openWindow(id: DepartementWindowView.windowID, value: dep.codeInsee) })
                            .tag(SidebarDestination.departement(dep.codeInsee))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Sources : ancré tout en bas de la sidebar, hors de la liste.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { selection.wrappedValue = .screen(.sources) } label: {
                HStack(spacing: 0) {
                    Self.rowLabel("Sources", systemImage: "books.vertical", bold: state.screen == .sources)
                    Spacer(minLength: 4)
                }
                .padding(.leading, iconLeading ?? 12).padding(.trailing, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .coordinateSpace(name: "sidebar")
        .onPreferenceChange(IconLeadingKey.self) { iconLeading = $0 }
    }
}

/// Couleur forcée (noir en clair, blanc en sombre) tant que la fenêtre est
/// active ; en arrière-plan, l'icône reprend le style par défaut de la sidebar.
private struct ActiveBadgeStyle: ViewModifier {
    @Environment(\.controlActiveState) private var activeState
    @ViewBuilder func body(content: Content) -> some View {
        if activeState == .inactive { content } else { content.foregroundStyle(.primary) }
    }
}

private struct IconLeadingKey: PreferenceKey {
    static var defaultValue: CGFloat? { nil }
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}
