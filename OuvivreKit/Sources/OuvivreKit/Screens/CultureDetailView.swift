import SwiftUI

/// Fenêtre séparée regroupant les données culturelles d'un département
/// (ouverte par l'icône de la rubrique CULTURE de l'inspecteur) : Musées,
/// Lieux du patrimoine et Festivals, chaque longue liste répartie sur
/// plusieurs colonnes.
public struct CultureDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }
    /// Identifiant de la scène `WindowGroup(for: String.self)` déclarée par
    /// l'app — la valeur passée à `openWindow` est le code du département.
    public static let windowID = "culture-detail"

    let departementCode: String
    @Environment(\.openURL) private var openURL
    @StateObject private var theme = ClassicTheme()
    /// Instance propre à cette fenêtre, utilisée pour les favoris seulement
    /// (synchronisés avec la fenêtre principale via `UserDefaults`).
    @StateObject private var state = ClassicState()
    /// Rubriques repliées par l'utilisateur — toutes dépliées par défaut.
    @State private var mapFocusTick = 0
    @State private var collapsedSections: Set<String> = ["Musées", "Lieux du patrimoine", "Festivals"]

    /// Mode intégré (vue Département de la sidebar) : sans en-tête, carte,
    /// défilement ni cadre de fenêtre — le parent les fournit.
    let embedded: Bool

    public init(departementCode: String, embedded: Bool = false) {
        self.departementCode = departementCode
        self.embedded = embedded
    }

    private var departementName: String {
        FranceGeoData.departements.first { $0.codeInsee == departementCode }?.nom ?? departementCode
    }

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 16, alignment: .topLeading)]

    public var body: some View {
        OptionalScroll(enabled: !embedded) {
            VStack(alignment: .leading, spacing: 28) {
                if !embedded {
                    DepartementDetailHeader(departementCode: departementCode, name: departementName, accent: theme.accent, state: state) { mapFocusTick += 1 }
                    DepartementMapCard(name: departementName, accent: theme.accent, focusCoordinate: FranceGeoData.chefsLieuxCoordinates[departementCode], focusTick: mapFocusTick, roundedFont: true)
                }

                museesSection
                patrimoineSection
                festivalsSection
            }
            .padding(embedded ? 0 : 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .modifier(WindowStyle(enabled: !embedded))
        .environmentObject(theme)
    }

    // MARK: Sections

    private var museesSection: some View {
        let all = InspectorPanelView.dedupedNames(CultureScores.names(forDepartementCode: departementCode, criterionKey: "musees"), mergeVariants: true)
        let microFolies = all.filter { $0.localizedCaseInsensitiveContains("micro-folie") || $0.localizedCaseInsensitiveContains("microfolie") }
        let regular = all.filter { !microFolies.contains($0) }
        return section(title: "Musées", icon: "photo.artframe", count: all.count) {
            alphabeticalGrid(regular, criterionKey: "musees")
            if !regular.isEmpty, !microFolies.isEmpty { Divider() }
            let sortedMicroFolies = microFolies.sorted {
                InspectorPanelView.titleCased($0).localizedStandardCompare(InspectorPanelView.titleCased($1)) == .orderedAscending
            }
            grid(sortedMicroFolies, criterionKey: "musees")
        }
    }

    private var patrimoineSection: some View {
        let monuments = InspectorPanelView.dedupedNames(CultureScores.names(forDepartementCode: departementCode, criterionKey: "patrimoine"), mergeVariants: false)
        let spr = CultureScores.names(forDepartementCode: departementCode, criterionKey: "spr")
        return section(title: "Lieux du patrimoine", icon: "building.classical.columns", count: monuments.count) {
            alphabeticalGrid(monuments, criterionKey: "patrimoine")
            if !spr.isEmpty {
                Divider()
                (Text("Sites patrimoniaux remarquables").foregroundStyle(c.ink) + Text(" · \(spr.count)").foregroundStyle(c.faint))
                    .font(CFont.rounded(12, weight: .semibold))
                grid(spr, criterionKey: "spr")
            }
        }
    }

    private var festivalsSection: some View {
        let names = InspectorPanelView.dedupedNames(CultureScores.names(forDepartementCode: departementCode, criterionKey: "festivals"), mergeVariants: false)
        let byDiscipline = Dictionary(grouping: names) {
            CultureScores.discipline(forDepartementCode: departementCode, criterionKey: "festivals", name: $0) ?? "Autre"
        }
        let ordered = byDiscipline.keys.sorted {
            if $0 == "Autre" || $1 == "Autre" { return $1 == "Autre" && $0 != "Autre" }
            return byDiscipline[$0]!.count != byDiscipline[$1]!.count ? byDiscipline[$0]!.count > byDiscipline[$1]!.count : $0 < $1
        }
        return section(title: "Festivals", icon: "fireworks", count: names.count) {
            ForEach(ordered, id: \.self) { discipline in
                VStack(alignment: .leading, spacing: 8) {
                    (Text(discipline.prefix(1).uppercased() + discipline.dropFirst().lowercased()).foregroundStyle(c.ink) + Text(" · \(byDiscipline[discipline]!.count)").foregroundStyle(c.faint))
                        .font(CFont.rounded(11, weight: .semibold))
                        .padding(.top, 12)
                    alphabeticalGrid(byDiscipline[discipline]!, criterionKey: "festivals")
                }
            }
        }
    }

    /// Regroupe des noms par ordre alphabétique, une entrée par lettre de
    /// changement de rang (utilisé pour la liste des lieux du patrimoine).
    private struct AlphabeticalGroup: Identifiable {
        let letter: String
        let names: [String]
        var id: String { letter }
    }

    /// Premier chiffre ou lettre d'un nom, en ignorant toute ponctuation de
    /// tête (guillemets, etc.) — ex. `"villa "le manoir""` classée sous L,
    /// pas sous `"`. Un chiffre de tête est conservé tel quel et classé
    /// avant les lettres ; une lettre accentuée est classée avec sa lettre
    /// de base (É → E).
    private func leadingLetter(_ name: String) -> String {
        let displayName = InspectorPanelView.titleCased(name)
        guard let char = displayName.first(where: { $0.isLetter || $0.isNumber }) else { return "" }
        if char.isNumber { return String(char) }
        return String(char).folding(options: .diacriticInsensitive, locale: nil).uppercased()
    }

    private func alphabeticalGroups(_ names: [String]) -> [AlphabeticalGroup] {
        let sorted = names.sorted {
            InspectorPanelView.titleCased($0).localizedStandardCompare(InspectorPanelView.titleCased($1)) == .orderedAscending
        }
        var groups: [AlphabeticalGroup] = []
        for name in sorted {
            let letter = leadingLetter(name)
            if let last = groups.last, last.letter == letter {
                groups[groups.count - 1] = AlphabeticalGroup(letter: letter, names: last.names + [name])
            } else {
                groups.append(AlphabeticalGroup(letter: letter, names: [name]))
            }
        }
        return groups
    }

    /// Liste répartie en grille, triée par ordre alphabétique et précédée
    /// d'une lettre de rang à chaque changement.
    private func alphabeticalGrid(_ names: [String], criterionKey: String) -> some View {
        ForEach(alphabeticalGroups(names)) { group in
            VStack(alignment: .leading, spacing: 8) {
                Text(group.letter)
                    .font(CFont.rounded(13, weight: .bold))
                    .foregroundStyle(c.ink)
                    .padding(.leading, 23)
                grid(group.names, criterionKey: criterionKey)
            }
        }
    }

    // MARK: Briques

    private func section<Content: View>(title: String, icon: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        let isCollapsed = collapsedSections.contains(title)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed { collapsedSections.remove(title) } else { collapsedSections.insert(title) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c.faint)
                        .frame(width: 11)
                    Image(systemName: icon).foregroundStyle(theme.accent)
                    (Text(title).foregroundStyle(c.body) + Text(" · \(count)").foregroundStyle(c.faint))
                        .font(CFont.rounded(13, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if count == 0 {
                    Text("Aucune donnée pour ce département.")
                        .font(CFont.rounded(13)).foregroundStyle(c.faint)
                } else {
                    content()
                }
            }
        }
    }

    /// Liste répartie sur autant de colonnes que la largeur de la fenêtre
    /// en permet.
    private func grid(_ names: [String], criterionKey: String) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(names, id: \.self) { name in
                Button {
                    if let site = CultureScores.url(forDepartementCode: departementCode, criterionKey: criterionKey, name: name) {
                        openURL(site)
                    } else {
                        let query = InspectorPanelView.titleCased(name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://www.google.com/search?q=\(query)") { openURL(url) }
                    }
                } label: {
                    Text(InspectorPanelView.titleCased(name))
                        .font(CFont.rounded(13))
                        .lineSpacing(3)
                        .foregroundStyle(c.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WindowStyle: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.departementDetailWindow() } else { content }
    }
}
