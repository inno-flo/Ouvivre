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

    private var isTous: Bool { state.screen == .favoris && state.selectedDepartementCode == nil }

    /// Départements favoris, dans l'ordre alphabétique — la liste suit
    /// `favoriteDepartementCodes` (ajout/retrait depuis n'importe où).
    private var favoriteDepartements: [FranceGeoData.DepartementScore] {
        FranceGeoData.departements
            .filter { state.favoriteDepartementCodes.contains($0.codeInsee) }
            .sorted { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
    }

    private var topCodes: Set<String> { FavorisView.topDepartementCodes(among: state.favoriteDepartementCodes) }

    public var body: some View {
        List(selection: selection) {
            Section {
                ForEach(derived.navSteps) { item in
                    NavItemRow(item: item).tag(SidebarDestination.screen(item.screen))
                }
            } header: {
                Text("Sélection").foregroundStyle(.secondary)
            }

            Section {
                if favoritesExpanded {
                    HStack(spacing: 9) {
                        Image(systemName: state.favoriteDepartementCodes.isEmpty ? "star" : "star.fill").frame(width: 16).foregroundStyle(state.favoriteDepartementCodes.isEmpty ? Color.primary : ClassicTheme.favorite)
                        Text("Tous").font(.system(size: 13, weight: isTous ? .bold : .regular))
                        Spacer(minLength: 4)
                        // Même corps que les compteurs de la sidebar de PierreVincent (13 pt,
                        // gras quand la rubrique est sélectionnée).
                        Text("\(state.favoriteDepartementCodes.count)")
                            .font(.system(size: 13))
                            .fontWeight(isTous ? .bold : .regular)
                            .opacity(0.5)
                    }
                    .tag(SidebarDestination.screen(.favoris))
                    ForEach(favoriteDepartements, id: \.codeInsee) { dep in
                        HStack(spacing: 9) {
                            Image(systemName: "mappin").frame(width: 16)
                            Text(dep.nom).font(.system(size: 13, weight: state.selectedDepartementCode == dep.codeInsee ? .bold : .regular))
                            Spacer(minLength: 4)
                            if topCodes.contains(dep.codeInsee) {
                                Image(systemName: "checkmark.seal.text.page").foregroundStyle(ClassicTheme.favorite)
                                    .help("Le plus de meilleures valeurs")
                            }
                        }
                        .tag(SidebarDestination.departement(dep.codeInsee))
                    }
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { favoritesExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: favoritesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).frame(width: 10)
                        Image(systemName: state.favoriteDepartementCodes.isEmpty ? "star" : "star.fill")
                            .foregroundStyle(state.favoriteDepartementCodes.isEmpty ? Color.secondary : ClassicTheme.favorite)
                        Text("Favoris")
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
