import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Contenu de l'inspecteur — panneau d'informations texte, sans carte
/// (retirée de l'inspecteur sur tous les écrans : chaque écran qui a besoin
/// d'une carte l'affiche en plein cadre dans le panneau central, avec ses
/// propres boutons de contrôle dans la toolbar).
public struct InspectorPanelView: View {
    @EnvironmentObject var theme: ClassicTheme
    @Environment(\.openURL) private var openURL
    let title: String
    /// Critère (libellé + clé `CultureScores.criterionKeys`) et département
    /// courant — `nil` en dehors de Big Mac ou tant qu'aucun département
    /// n'a de code résolu (nom non trouvé dans `FranceGeoData`).
    let activeCultureCriteria: [(label: String, key: String)]
    let departementCode: String?
    /// Fiche pays (nom + faits) déplacée ici depuis le bloc "Pays" de Big
    /// Mac, qui ne garde que les capsules de choix — vide en dehors de Big
    /// Mac. Toujours affichée (indépendante de la sélection de département).
    let countryName: String
    let countryFacts: [LabeledValue]
    /// Partage l'état ouvert/replié avec le bloc "Pays" de Big Mac
    /// (`state.bigMacExpandedPays`) plutôt qu'un état local indépendant :
    /// replier le bloc dans la colonne de réglages replie aussi cette
    /// section (et inversement).
    @Binding var isCountryExpanded: Bool

    // Chaque section Culture démarre dépliée — l'utilisateur replie celles
    // qui ne l'intéressent pas plutôt que l'inverse.
    @State private var collapsedKeys: Set<String> = []

    public init(title: String, activeCultureCriteria: [(label: String, key: String)], departementCode: String?, countryName: String = "", countryFacts: [LabeledValue] = [], isCountryExpanded: Binding<Bool> = .constant(true)) {
        self.title = title
        self.activeCultureCriteria = activeCultureCriteria
        self.departementCode = departementCode
        self.countryName = countryName
        self.countryFacts = countryFacts
        self._isCountryExpanded = isCountryExpanded
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !countryName.isEmpty {
                    countrySection
                }

                if !title.isEmpty {
                    Eyebrow("DÉPARTEMENT", color: ClassicTheme.faint)
                    HStack(spacing: 8) {
                        Text(title)
                            .font(CFont.sans(20, weight: .semibold))
                            .foregroundStyle(ClassicTheme.ink)
                        if let code = departementCode {
                            Text(code)
                                .font(CFont.sans(20, weight: .semibold))
                                .foregroundStyle(ClassicTheme.ink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(ClassicTheme.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }

                    ForEach(activeCultureCriteria, id: \.key) { criterion in
                        criterionSection(criterion)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClassicTheme.sidebarBg.opacity(0.935))
    }

    private var countrySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isCountryExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Eyebrow("PAYS", color: ClassicTheme.faint)
                    Spacer()
                    Image(systemName: isCountryExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ClassicTheme.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCountryExpanded {
                Text(countryName)
                    .font(CFont.sans(20, weight: .semibold))
                    .foregroundStyle(ClassicTheme.ink)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(countryFacts) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.key).font(CFont.sans(13)).foregroundStyle(ClassicTheme.faint)
                            Text(f.value).font(CFont.sans(15, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    /// Le libellé du critère (repliable), suivi des noms des sites/événements
    /// de ce département pour ce critère (musées, festivals, ou communes du
    /// site patrimonial remarquable pour "Lieux du patrimoine").
    private func criterionSection(_ criterion: (label: String, key: String)) -> some View {
        let names = departementCode.map { CultureScores.names(forDepartementCode: $0, criterionKey: criterion.key) } ?? []
        let isCollapsed = collapsedKeys.contains(criterion.key)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed { collapsedKeys.remove(criterion.key) } else { collapsedKeys.insert(criterion.key) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                    Text(criterion.label.uppercased())
                        .font(CFont.mono(11, weight: .semibold))
                        .foregroundStyle(ClassicTheme.faint)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ClassicTheme.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if names.isEmpty {
                    Text("Aucune donnée pour ce département.")
                        .font(CFont.sans(13))
                        .foregroundStyle(ClassicTheme.faint)
                } else if criterion.key == "musees" {
                    // Les Micro-Folies (réseau de petits équipements
                    // numériques, distinct des musées classiques) sont
                    // reléguées en fin de liste, séparées par un filet.
                    let microFolies = names.filter { $0.localizedCaseInsensitiveContains("micro-folie") || $0.localizedCaseInsensitiveContains("microfolie") }
                    let regular = names.filter { !microFolies.contains($0) }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(regular, id: \.self) { name in
                            nameRow(name)
                        }
                        if !regular.isEmpty, !microFolies.isEmpty {
                            Divider().padding(.vertical, 4)
                        }
                        ForEach(microFolies, id: \.self) { name in
                            nameRow(name)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(names, id: \.self) { name in
                            nameRow(name)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// Nom cliquable (curseur pointeur, mais pas de style lien visible sur
    /// le texte) — ouvre une recherche web sur ce nom dans le navigateur par
    /// défaut. macOS n'expose pas d'API publique pour interroger le moteur
    /// de recherche par défaut d'une app tierce (seule Safari applique ce
    /// réglage à sa propre barre d'adresse) ; on utilise donc une recherche
    /// Google, ouverte via le navigateur par défaut du système.
    private func nameRow(_ name: String) -> some View {
        Button {
            let query = Self.titleCased(name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://www.google.com/search?q=\(query)") { openURL(url) }
        } label: {
            Text(Self.titleCased(name))
                .font(CFont.sans(13))
                .foregroundStyle(ClassicTheme.body)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            #if os(macOS)
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            #endif
        }
    }

    /// Prépositions/articles français qui restent en minuscules dans une
    /// casse de titre, sauf en position initiale (ex. "Château de Chambord",
    /// mais "Le Havre").
    private static let lowercasedParticles: Set<String> = [
        "de", "du", "des", "d'", "la", "le", "les", "l'", "et", "en", "à", "au", "aux", "sur"
    ]

    /// Les noms bruts mélangent TOUT MAJUSCULES et tout minuscules — on les
    /// remet en casse de titre (mot par mot, prépositions/articles en
    /// minuscules sauf en premier mot) pour un affichage cohérent. Simplifié :
    /// suffisant pour des noms de lieux/événements affichés en liste, sans
    /// prétendre à une capitalisation typographique parfaite (ex. les
    /// apostrophes type "d'Azur" ne sont pas toutes détectées).
    /// Élisions françaises ("d'", "l'", "n'", "j'", "c'", "m'", "t'", "s'",
    /// "qu'") collées au mot suivant (ex. "d'Histoire", "l'Aventure") — la
    /// particule reste en minuscule (sauf en tout premier mot), la lettre
    /// après l'apostrophe se capitalise comme un mot normal.
    private static let elisionPrefixes = ["qu'", "d'", "l'", "n'", "j'", "c'", "m'", "t'", "s'"]

    private static func titleCased(_ name: String) -> String {
        let words = name.lowercased().split(separator: " ")
        return words.enumerated().map { index, word -> String in
            let word = String(word)
            if index > 0, lowercasedParticles.contains(word) { return word }
            if let prefix = elisionPrefixes.first(where: { word.hasPrefix($0) }), word.count > prefix.count {
                let rest = word.dropFirst(prefix.count)
                let capitalizedRest = rest.prefix(1).uppercased() + rest.dropFirst()
                // Premier mot : la particule elle-même se capitalise aussi
                // (ex. "D'Histoire naturelle du Muséum").
                return (index == 0 ? prefix.prefix(1).uppercased() + prefix.dropFirst() : prefix) + capitalizedRest
            }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
