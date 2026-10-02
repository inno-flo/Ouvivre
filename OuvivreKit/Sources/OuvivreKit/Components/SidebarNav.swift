import SwiftUI

/// The native sidebar list: "Sélecteur" (steps) + "Outils" sections, plus a
/// "Sources" row — selection and highlighting are driven by `List`. Row and
/// header font sizes mirror the PierreVincent project's sidebar convention:
/// 13pt (`NSFont.systemFontSize`) for row labels, 11pt for section headers,
/// headers always staying smaller than the labels they group.
struct SidebarNav: View {
    let selection: Binding<SidebarDestination?>
    @EnvironmentObject private var state: ClassicState
    @State private var favoritesExpanded = true
    /// Abscisse de l'icône de Sélecteur, mesurée : Sources (hors de la liste) s'y aligne.
    @State private var iconLeading: CGFloat?

    /// Colonne de droite commune au chevron de l'en-tête et au compteur de
    /// « Tous » : leur centre tombe sur celui du bouton de fermeture de la sidebar
    /// (≈ 25 pt du bord droit, contre ≈ 10 pt de marge intérieure des lignes).
    private static let trailingColumnWidth: CGFloat = 30

    private var isTous: Bool { state.screen == .favoris && state.selectedDepartementCode == nil }

    /// Départements favoris, badge `checkmark.seal` en tête, puis ordre alphabétique — la liste suit
    /// `favoriteDepartementCodes` (ajout/retrait depuis n'importe où).
    private func favoriteDepartements(topCodes: Set<String>) -> [FranceGeoData.DepartementScore] {
        FranceGeoData.departements
            .filter { state.favoriteDepartementCodes.contains($0.codeInsee) }
            .sorted {
                let a = topCodes.contains($0.codeInsee), b = topCodes.contains($1.codeInsee)
                return a != b ? a : $0.nom.localizedStandardCompare($1.nom) == .orderedAscending
            }
    }

    var body: some View {
        let topCodes = FavorisView.topDepartementCodes(among: state.favoriteDepartementCodes)
        List(selection: selection) {
            // Sélecteur : en tête de la sidebar, sans en-tête de section.
            HStack(spacing: 9) {
                Image(systemName: "list.bullet.clipboard").frame(width: 16)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: IconLeadingKey.self, value: proxy.frame(in: .named("sidebar")).minX)
                    })
                Text("Sélecteur").font(.system(size: 13, weight: state.screen == .selecteur && state.selectedDepartementCode == nil ? .bold : .regular))
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
                        // Titre et compteur partagent la même police (13 pt, gras quand la
                        // rubrique est sélectionnée).
                        HStack(spacing: 9) {
                            Image(systemName: "star").frame(width: 16).modifier(ActiveBadgeStyle())
                            Text("Tous")
                            Spacer(minLength: 4)
                            Text("\(state.favoriteDepartementCodes.count)")
                                .opacity(0.5)
                                .frame(width: Self.trailingColumnWidth)
                        }
                        .font(.system(size: 13, weight: isTous ? .bold : .regular))
                        .tag(SidebarDestination.screen(.favoris))
                        ForEach(favoriteDepartements(topCodes: topCodes), id: \.codeInsee) { dep in
                            HStack(spacing: 9) {
                                if topCodes.contains(dep.codeInsee) {
                                    Image(systemName: "checkmark.seal").frame(width: 16).modifier(ActiveBadgeStyle())
                                } else {
                                    Image(systemName: "mappin").frame(width: 16)
                                }
                                Text(dep.nom).font(.system(size: 13, weight: state.selectedDepartementCode == dep.codeInsee ? .bold : .regular))
                                Spacer(minLength: 4)
                            }
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
                HStack(spacing: 9) {
                    Image(systemName: "books.vertical").frame(width: 16)
                    Text("Sources").font(.system(size: 13, weight: state.screen == .sources ? .bold : .regular))
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
