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
    /// Instance propre à cette fenêtre, utilisée pour les favoris seulement
    /// (synchronisés avec la fenêtre principale via `UserDefaults`).
    @StateObject private var state = ClassicState()
    /// Rubriques repliées par l'utilisateur — toutes repliées par défaut.
    @State private var collapsedSections: Set<String> = ["Musées", "Lieux du patrimoine", "Festivals"]

    /// Mode intégré (vue Département de la sidebar) : sans en-tête, carte,
    /// défilement ni cadre de fenêtre — le parent les fournit.
    let embedded: Bool

    public init(departementCode: String, embedded: Bool = false) {
        self.departementCode = departementCode
        self.embedded = embedded
    }

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 16, alignment: .topLeading)]

    public var body: some View {
        OptionalScroll(enabled: !embedded) {
            VStack(alignment: .leading, spacing: 28) {
                if !embedded {
                    DepartementHeaderAndMap(departementCode: departementCode, state: state)
                }

                museesSection
                patrimoineSection
                festivalsSection
            }
            .padding(embedded ? 0 : 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .departementDetailWindow(!embedded)
    }

    // MARK: Sections

    private func names(_ criterionKey: String, mergeVariants: Bool = false) -> [String] {
        CultureScores.dedupedNames(CultureScores.names(forDepartementCode: departementCode, criterionKey: criterionKey), mergeVariants: mergeVariants)
    }

    private var museesSection: some View {
        let all = names("musees", mergeVariants: true)
        let regular = all.filter { !CultureScores.isMicroFolie($0) }
        let microFolies = CultureScores.sortedByTitle(all.filter(CultureScores.isMicroFolie))
        return section(title: "Musées", icon: "photo.artframe", count: all.count) {
            alphabeticalGrid(regular, criterionKey: "musees")
            if !regular.isEmpty, !microFolies.isEmpty { Divider() }
            grid(microFolies, criterionKey: "musees")
        }
    }

    private var patrimoineSection: some View {
        let monuments = names("patrimoine")
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
        let festivals = names("festivals")
        return section(title: "Festivals", icon: "fireworks", count: festivals.count) {
            ForEach(CultureScores.festivalsByDiscipline(forDepartementCode: departementCode, names: festivals), id: \.discipline) { group in
                VStack(alignment: .leading, spacing: 8) {
                    (Text(group.discipline.prefix(1).uppercased() + group.discipline.dropFirst().lowercased()).foregroundStyle(c.ink) + Text(" · \(group.names.count)").foregroundStyle(c.faint))
                        .font(CFont.rounded(11, weight: .semibold))
                        .padding(.top, 12)
                    alphabeticalGrid(group.names, criterionKey: "festivals")
                }
            }
        }
    }

    /// Regroupe des noms par ordre alphabétique, une entrée par lettre de
    /// changement de rang (utilisé pour la liste des lieux du patrimoine).
    private struct AlphabeticalGroup: Identifiable {
        let letter: String
        var names: [String]
        var id: String { letter }
    }

    /// Premier chiffre ou lettre d'un nom, en ignorant toute ponctuation de
    /// tête (guillemets, etc.) — ex. `"villa "le manoir""` classée sous L,
    /// pas sous `"`. Un chiffre de tête est conservé tel quel et classé
    /// avant les lettres ; une lettre accentuée est classée avec sa lettre
    /// de base (É → E).
    private func leadingLetter(_ name: String) -> String {
        let displayName = CultureScores.titleCased(name)
        guard let char = displayName.first(where: { $0.isLetter || $0.isNumber }) else { return "" }
        if char.isNumber { return String(char) }
        return String(char).folding(options: .diacriticInsensitive, locale: nil).uppercased()
    }

    private func alphabeticalGroups(_ names: [String]) -> [AlphabeticalGroup] {
        var groups: [AlphabeticalGroup] = []
        for name in CultureScores.sortedByTitle(names) {
            let letter = leadingLetter(name)
            if groups.last?.letter == letter {
                groups[groups.count - 1].names.append(name)
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
                    Image(systemName: icon).foregroundStyle(ClassicTheme.accent)
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
                    if let url = CultureScores.link(forDepartementCode: departementCode, criterionKey: criterionKey, name: name) { openURL(url) }
                } label: {
                    Text(CultureScores.titleCased(name))
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
