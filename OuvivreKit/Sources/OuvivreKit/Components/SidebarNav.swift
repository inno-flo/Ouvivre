import SwiftUI

/// The native sidebar list: "Sélecteur" (steps) + "Outils" sections, plus a
/// "Sources" row — selection and highlighting are driven by `List`. Row and
/// header font sizes mirror the PierreVincent project's sidebar convention:
/// 13pt (`NSFont.systemFontSize`) for row labels, 11pt for section headers,
/// headers always staying smaller than the labels they group.
public struct SidebarNav: View {
    let derived: ClassicDerived
    let selection: Binding<SidebarDestination?>
    @EnvironmentObject private var state: ClassicState
    @State private var favoritesExpanded = true

    public init(derived: ClassicDerived, selection: Binding<SidebarDestination?>) {
        self.derived = derived
        self.selection = selection
    }

    /// Colonne de droite commune au chevron de l'en-tête et au compteur de
    /// « Tous » : leur centre tombe sur celui du bouton de fermeture de la sidebar
    /// (≈ 25 pt du bord droit, contre ≈ 10 pt de marge intérieure des lignes).
    private static let trailingColumnWidth: CGFloat = 30

    private var isTous: Bool { state.screen == .favoris && state.selectedDepartementCode == nil }

    /// Départements favoris, badge `checkmark.seal` en tête, puis ordre alphabétique — la liste suit
    /// `favoriteDepartementCodes` (ajout/retrait depuis n'importe où).
    private var favoriteDepartements: [FranceGeoData.DepartementScore] {
        FranceGeoData.departements
            .filter { state.favoriteDepartementCodes.contains($0.codeInsee) }
            .sorted {
                let a = topCodes.contains($0.codeInsee), b = topCodes.contains($1.codeInsee)
                return a != b ? a : $0.nom.localizedStandardCompare($1.nom) == .orderedAscending
            }
    }

    private var topCodes: Set<String> { FavorisView.topDepartementCodes(among: state.favoriteDepartementCodes) }

    public var body: some View {
        List(selection: selection) {
            // Sélecteur : en tête de la sidebar, sans en-tête de section.
            ForEach(derived.navSteps) { item in
                NavItemRow(item: item).tag(SidebarDestination.screen(item.screen))
            }

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
                        Image(systemName: "star").frame(width: 16).foregroundStyle(.primary)
                        Text("Tous")
                        Spacer(minLength: 4)
                        Text("\(state.favoriteDepartementCodes.count)")
                            .opacity(0.5)
                            .frame(width: Self.trailingColumnWidth)
                    }
                    .font(.system(size: 13, weight: isTous ? .bold : .regular))
                    .tag(SidebarDestination.screen(.favoris))
                    ForEach(favoriteDepartements, id: \.codeInsee) { dep in
                        HStack(spacing: 9) {
                            if topCodes.contains(dep.codeInsee) {
                                Image(systemName: "checkmark.seal").frame(width: 16).foregroundStyle(.primary)
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
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct NavItemRow: View {
    let item: NavItem

    /// Icons for the "Sélecteur" screens only — matches the request's list;
    /// other rows (Outils, Sources) render without a leading icon.
    private var icon: String? {
        switch item.screen {
        case .selecteur: "chart.bar.horizontal.page"
        case .pays: "globe.europe.africa"
        case .geo2: "map"
        case .affiner: "bus"
        case .meteo: "thermometer.sun"
        case .ville: "mappin.and.ellipse"
        default: nil
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(systemName: icon).frame(width: 16)
            }
            Text(item.label).font(.system(size: 13, weight: item.active ? .bold : .regular))
            Spacer(minLength: 4)
            if let meta = item.meta {
                Text(meta).font(CFont.mono(10)).opacity(0.5)
            }
        }
    }
}
