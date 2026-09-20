import SwiftUI

/// Fenêtre séparée regroupant les données culturelles d'un département
/// (ouverte par l'icône de la rubrique CULTURE de l'inspecteur) : Musées,
/// Lieux du patrimoine et Festivals, chaque longue liste répartie sur
/// plusieurs colonnes.
public struct CultureDetailView: View {
    /// Identifiant de la scène `WindowGroup(for: String.self)` déclarée par
    /// l'app — la valeur passée à `openWindow` est le code du département.
    public static let windowID = "culture-detail"

    let departementCode: String
    @Environment(\.openURL) private var openURL
    @StateObject private var theme = ClassicTheme()
    /// Rubriques repliées par l'utilisateur — toutes dépliées par défaut.
    @State private var collapsedSections: Set<String> = []

    public init(departementCode: String) { self.departementCode = departementCode }

    private var departementName: String {
        FranceGeoData.departements.first { $0.codeInsee == departementCode }?.nom ?? departementCode
    }

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 16, alignment: .topLeading)]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Text(departementName)
                        .font(CFont.sans(24, weight: .semibold))
                    Text(departementCode)
                        .font(CFont.sans(24, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(ClassicTheme.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    if let chefLieu = FranceGeoData.chefsLieux[departementCode] {
                        Text("Chef-lieu : \(chefLieu)")
                            .font(CFont.sans(14)).foregroundStyle(ClassicTheme.faint)
                    }
                }

                museesSection
                patrimoineSection
                festivalsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 620, minHeight: 420)
        .environmentObject(theme)
    }

    // MARK: Sections

    private var museesSection: some View {
        let all = InspectorPanelView.dedupedNames(CultureScores.names(forDepartementCode: departementCode, criterionKey: "musees"), mergeVariants: true)
        let microFolies = all.filter { $0.localizedCaseInsensitiveContains("micro-folie") || $0.localizedCaseInsensitiveContains("microfolie") }
        let regular = all.filter { !microFolies.contains($0) }
        return section(title: "MUSÉES", icon: "photo.artframe", count: all.count) {
            grid(regular, criterionKey: "musees")
            if !regular.isEmpty, !microFolies.isEmpty { Divider() }
            grid(microFolies, criterionKey: "musees")
        }
    }

    private var patrimoineSection: some View {
        let monuments = InspectorPanelView.dedupedNames(CultureScores.names(forDepartementCode: departementCode, criterionKey: "patrimoine"), mergeVariants: false)
        let spr = CultureScores.names(forDepartementCode: departementCode, criterionKey: "spr")
        return section(title: "LIEUX DU PATRIMOINE", icon: "building.classical.columns", count: monuments.count) {
            grid(monuments, criterionKey: "patrimoine")
            if !spr.isEmpty {
                Divider()
                Text("SITES PATRIMONIAUX REMARQUABLES · \(spr.count)")
                    .font(CFont.mono(10, weight: .semibold)).foregroundStyle(ClassicTheme.faint)
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
        return section(title: "FESTIVALS", icon: "fireworks", count: names.count) {
            ForEach(ordered, id: \.self) { discipline in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(discipline.uppercased()) · \(byDiscipline[discipline]!.count)")
                        .font(CFont.mono(10, weight: .semibold)).foregroundStyle(ClassicTheme.faint)
                    grid(byDiscipline[discipline]!, criterionKey: "festivals")
                }
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
                    Image(systemName: icon).foregroundStyle(theme.accent)
                    Text("\(title) · \(count)")
                        .font(CFont.mono(12, weight: .semibold)).foregroundStyle(ClassicTheme.faint)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClassicTheme.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if count == 0 {
                    Text("Aucune donnée pour ce département.")
                        .font(CFont.sans(13)).foregroundStyle(ClassicTheme.faint)
                } else {
                    content()
                }
            }
        }
    }

    /// Liste répartie sur autant de colonnes que la largeur de la fenêtre
    /// en permet.
    private func grid(_ names: [String], criterionKey: String) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
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
                        .font(CFont.sans(13))
                        .lineSpacing(3)
                        .foregroundStyle(ClassicTheme.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
