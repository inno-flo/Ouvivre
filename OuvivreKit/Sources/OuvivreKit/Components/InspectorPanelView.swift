import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

/// Contenu de l'inspecteur — panneau d'informations texte, sans carte
/// (retirée de l'inspecteur sur tous les écrans : chaque écran qui a besoin
/// d'une carte l'affiche en plein cadre dans le panneau central, avec ses
/// propres boutons de contrôle dans la toolbar).
public struct InspectorPanelView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
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

    // Les catégories sont repliées par défaut, sauf Météo (toujours dépliée
    // par défaut) : seules les clés dépliées sont mémorisées, et remises à
    // cet état initial à chaque nouveau département.
    private static let defaultExpandedKeys: Set<String> = []
    @State private var expandedKeys: Set<String> = InspectorPanelView.defaultExpandedKeys

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
                if !countryName.isEmpty && departementCode == nil {
                    countrySection
                }

                // `mapState.title` vaut "France" par défaut (avant tout
                // clic sur un département) — n'affiche la section que
                // lorsqu'un vrai département est résolu, pas juste un
                // titre non vide.
                if let code = departementCode {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(title)
                                    .font(CFont.rounded(20, weight: .semibold))
                                    .foregroundStyle(ClassicTheme.ink)
                                Text(code)
                                    .font(CFont.rounded(18, weight: .semibold))
                                    .foregroundStyle(ClassicTheme.ink)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(ClassicTheme.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                            }
                            if let chefLieu = FranceGeoData.chefsLieux[code] {
                                HStack(spacing: 8) {
                                    Text(chefLieu)
                                        .font(CFont.rounded(18))
                                        .foregroundStyle(ClassicTheme.faint)
                                    Button {
                                        centerMap(onDepartement: code)
                                    } label: {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(CFont.rounded(18))
                                            .foregroundStyle(ClassicTheme.faint)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Centrer la carte sur \(chefLieu)")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 8)
                        Button {
                            state.toggleFavoriteDepartement(code)
                        } label: {
                            let isFavorite = state.favoriteDepartementCodes.contains(code)
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundStyle(isFavorite ? theme.accent : ClassicTheme.faint)
                        }
                        .buttonStyle(.plain)
                        .help(state.favoriteDepartementCodes.contains(code) ? "Retirer des favoris" : "Ajouter aux favoris")
                    }

                    // Rubrique CULTURE : regroupe les sous-rubriques actives
                    // (Musées, Lieux du patrimoine, Festivals) ; l'icône ouvre
                    // la fenêtre qui les réunit toutes les trois.
                    if !activeCultureCriteria.isEmpty {
                        HStack(spacing: 8) {
                            Eyebrow("CULTURE", color: ClassicTheme.faint, font: CFont.rounded(10, weight: .medium))
                            Spacer()
                            Button {
                                openWindow(id: CultureDetailView.windowID, value: code)
                            } label: {
                                Image(systemName: "interface.window.on.rectangle.dashed")
                                    .font(.system(size: 13))
                                    .foregroundStyle(ClassicTheme.faint)
                            }
                            .buttonStyle(.plain)
                            .help("Ouvrir les données culturelles dans une fenêtre")
                        }
                        .padding(.top, 4)
                    }

                    ForEach(activeCultureCriteria, id: \.key) { criterion in
                        criterionSection(criterion)
                    }

                    meteoSection(code)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: departementCode) { _, _ in expandedKeys = Self.defaultExpandedKeys }
        // Aucun fond personnalisé — comme la sidebar (`.listStyle(.sidebar)`),
        // l'inspecteur s'appuie sur le matériau translucide natif du système
        // derrière son contenu plutôt qu'une couleur/opacité fixée ici.
    }

    /// « Climats dominants » : sans le nombre ni le tiret, un climat par ligne,
    /// avec une majuscule initiale (« 4 — océanique, semi-continental » →
    /// « Océanique\nSemi-continental »).
    private static func displayValue(_ f: LabeledValue) -> String {
        guard f.key == "Climats dominants" else { return f.value }
        let parts = f.value.components(separatedBy: " — ")
        guard parts.count == 2 else { return f.value }
        return parts[1].components(separatedBy: ", ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "\n")
    }

    /// Recentre la carte sur la position du chef-lieu.
    private func centerMap(onDepartement code: String) {
        guard let coordinate = FranceGeoData.chefsLieuxCoordinates[code] else { return }
        let map = MapPanelState.shared
        map.coordinate = coordinate
        map.spanDegrees = 0.15
        map.recenterTick += 1
    }

    private var countrySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isCountryExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCountryExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ClassicTheme.faint)
                        .frame(width: 10)
                    Eyebrow("PAYS", color: ClassicTheme.faint, font: CFont.rounded(10, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCountryExpanded {
                Text(countryName)
                    .font(CFont.rounded(20, weight: .semibold))
                    .foregroundStyle(ClassicTheme.ink)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(countryFacts) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.key == "Population totale" ? "Population" : f.key).font(CFont.rounded(13)).foregroundStyle(ClassicTheme.faint)
                            Text(Self.displayValue(f)).font(CFont.rounded(15, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    /// Températures moyennes et précipitations mensuelles du département sur
    /// les 5 dernières années glissantes (données Météo-France, moyenne des
    /// postes du département — voir `MeteoMensuelle`).
    @ViewBuilder
    private func meteoSection(_ code: String) -> some View {
        let series = MeteoMensuelle.series(forDepartementCode: code)
        let isCollapsed = false
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Même en-tête que CULTURE (Eyebrow), sans chevron ni icône :
                // la rubrique Météo est toujours dépliée.
                Eyebrow("MÉTÉO", color: ClassicTheme.faint, font: CFont.rounded(10, weight: .medium))
                Spacer()

                // Ouvre la fenêtre de détail (comme le double-clic).
                Button {
                    openWindow(id: MeteoDetailView.windowID, value: code)
                } label: {
                    Image(systemName: "interface.window.on.rectangle")
                        .font(.system(size: 13))
                        .foregroundStyle(ClassicTheme.faint)
                }
                .buttonStyle(.plain)
                .help("Ouvrir le détail dans une fenêtre")
            }

            if !isCollapsed {
                if series.isEmpty {
                    Text("Aucune donnée pour ce département.")
                        .font(CFont.rounded(13))
                        .foregroundStyle(ClassicTheme.faint)
                } else {
                    Text("Température moyenne (°C)")
                        .font(CFont.rounded(12)).foregroundStyle(ClassicTheme.faint)
                    Chart(series.filter { $0.temperature != nil }) { point in
                        LineMark(x: .value("Mois", point.date, unit: .month), y: .value("°C", point.temperature ?? 0))
                            .foregroundStyle(theme.accent)
                            .interpolationMethod(.monotone)
                    }
                    .chartXAxis { Self.meteoXAxis }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 110)

                    Text("Précipitations (mm / mois)")
                        .font(CFont.rounded(12)).foregroundStyle(ClassicTheme.faint)
                    Chart(series.filter { $0.precipitation != nil }) { point in
                        BarMark(x: .value("Mois", point.date, unit: .month), y: .value("mm", point.precipitation ?? 0))
                            .foregroundStyle(theme.accent.opacity(point.partial ? 0.4 : 0.8))
                    }
                    .chartXAxis { Self.meteoXAxis }
                    .frame(height: 110)

                    if series.last?.partial == true {
                        Text("Dernier mois en cours (données partielles).")
                            .font(CFont.rounded(11)).foregroundStyle(ClassicTheme.faint)
                    }
                }
            }
        }
        .padding(.top, 4)
        // Double-clic : détail dans une fenêtre séparée (scène déclarée par l'app).
        .simultaneousGesture(TapGesture(count: 2).onEnded { openWindow(id: MeteoDetailView.windowID, value: code) })
        .help("Double-clic pour ouvrir le détail dans une fenêtre")
    }

    private static let meteoKey = "meteo"

    /// Icône de l'en-tête de chaque critère Culture.
    private static func headerIcon(forCriterionKey key: String) -> String {
        switch key {
        case "musees": "photo.artframe"
        case "patrimoine": "building.classical.columns"
        case "festivals": "fireworks"
        default: "checkmark.circle.fill"
        }
    }

    private static var meteoXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .year)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.year(), centered: false)
        }
    }

    /// Le libellé du critère (repliable), suivi des noms des sites/événements
    /// de ce département pour ce critère (musées, festivals, ou communes du
    /// site patrimonial remarquable pour "Lieux du patrimoine").
    private func criterionSection(_ criterion: (label: String, key: String)) -> some View {
        let rawNames = departementCode.map { CultureScores.names(forDepartementCode: $0, criterionKey: criterion.key) } ?? []
        let names = Self.dedupedNames(rawNames, mergeVariants: criterion.key == "musees")
        let isCollapsed = !expandedKeys.contains(criterion.key)
        let sprCount = departementCode.map { CultureScores.names(forDepartementCode: $0, criterionKey: "spr").count } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed { expandedKeys.insert(criterion.key) } else { expandedKeys.remove(criterion.key) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ClassicTheme.faint)
                        .frame(width: 10)
                    Image(systemName: Self.headerIcon(forCriterionKey: criterion.key))
                        .foregroundStyle(theme.accent)
                    Text(criterion.label)
                        .font(CFont.rounded(11, weight: .semibold))
                        .foregroundStyle(ClassicTheme.faint)
                    Spacer()
                    Text("\(names.count + (criterion.key == "patrimoine" ? sprCount : 0))")
                        .font(CFont.rounded(11, weight: .medium))
                        .foregroundStyle(ClassicTheme.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if names.isEmpty {
                    // Cette section n'est rendue que lorsque `departementCode`
                    // est résolu (voir `body`) — l'absence de données est
                    // donc bien celle d'un vrai département sans
                    // musées/festivals/patrimoine.
                    Text("Aucune donnée pour ce département.")
                        .font(CFont.rounded(13))
                        .foregroundStyle(ClassicTheme.faint)
                } else if criterion.key == "musees" {
                    // Les Micro-Folies (réseau de petits équipements
                    // numériques, distinct des musées classiques) sont
                    // reléguées en fin de liste, séparées par un filet.
                    let microFolies = names.filter { $0.localizedCaseInsensitiveContains("micro-folie") || $0.localizedCaseInsensitiveContains("microfolie") }
                    let regular = names.filter { !microFolies.contains($0) }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(regular, id: \.self) { name in
                            nameRow(name, criterionKey: criterion.key)
                        }
                        if !regular.isEmpty, !microFolies.isEmpty {
                            Divider().padding(.vertical, 4)
                        }
                        ForEach(microFolies, id: \.self) { name in
                            nameRow(name, criterionKey: criterion.key)
                        }
                    }
                } else if criterion.key == "festivals", let code = departementCode {
                    // Regroupés par discipline dominante (les plus fournies
                    // d'abord), festivals sans discipline en dernier.
                    let byDiscipline = Dictionary(grouping: names) {
                        CultureScores.discipline(forDepartementCode: code, criterionKey: "festivals", name: $0) ?? "Autre"
                    }
                    let ordered = byDiscipline.keys.sorted {
                        if $0 == "Autre" || $1 == "Autre" { return $1 == "Autre" && $0 != "Autre" }
                        return byDiscipline[$0]!.count != byDiscipline[$1]!.count ? byDiscipline[$0]!.count > byDiscipline[$1]!.count : $0 < $1
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ordered, id: \.self) { discipline in
                            VStack(alignment: .leading, spacing: 9) {
                                Text("\(discipline.uppercased()) · \(byDiscipline[discipline]!.count)")
                                    .font(CFont.rounded(10, weight: .semibold))
                                    .foregroundStyle(ClassicTheme.faint)
                                ForEach(byDiscipline[discipline]!, id: \.self) { name in
                                    nameRow(name, criterionKey: criterion.key)
                                }
                            }
                        }
                    }
                } else {
                    // Lazy : "Lieux du patrimoine" peut compter près de 2 000
                    // monuments historiques pour un seul département (Paris).
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(names, id: \.self) { name in
                            nameRow(name, criterionKey: criterion.key)
                        }
                        // Sites patrimoniaux remarquables (SPR) du département,
                        // après un filet — actif dès qu'"Important" ou
                        // "Déterminant" est réglé (la section n'existe que
                        // pour un critère au-dessus d'"Indifférent").
                        if criterion.key == "patrimoine", let code = departementCode {
                            let spr = CultureScores.names(forDepartementCode: code, criterionKey: "spr")
                            if !spr.isEmpty {
                                Divider().padding(.vertical, 6)
                                Text("SITES PATRIMONIAUX REMARQUABLES · \(spr.count)")
                                    .font(CFont.rounded(10, weight: .semibold))
                                    .foregroundStyle(ClassicTheme.faint)
                                ForEach(spr, id: \.self) { name in
                                    nameRow(name, criterionKey: "spr")
                                }
                            }
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
    private func nameRow(_ name: String, criterionKey: String) -> some View {
        Button {
            // Site officiel quand les données en fournissent un (festivals),
            // sinon recherche web sur le nom.
            if let code = departementCode, let site = CultureScores.url(forDepartementCode: code, criterionKey: criterionKey, name: name) {
                openURL(site)
                return
            }
            let query = Self.titleCased(name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://www.google.com/search?q=\(query)") { openURL(url) }
        } label: {
            Text(Self.titleCased(name))
                .font(CFont.rounded(13))
                .lineSpacing(3)
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

    /// Élisions sans apostrophe : certaines sources (ex. le CSV des sites
    /// patrimoniaux remarquables) séparent la particule élidée par une
    /// espace au lieu d'une apostrophe collée ("ST SYMPHORIEN D OZON" plutôt
    /// que "St Symphorien d'Ozon"), ce qui fait capitaliser le "D" comme un
    /// mot à part entière. On rejoint ces mots isolés au suivant avec une
    /// apostrophe avant la casse de titre normale.
    private static let standaloneElisionLetters: Set<String> = ["d", "l", "n", "j", "c", "m", "t", "s", "qu"]

    private static func mergeStandaloneElisions(_ words: [Substring]) -> [String] {
        var merged: [String] = []
        var i = 0
        while i < words.count {
            let word = String(words[i])
            if standaloneElisionLetters.contains(word), i + 1 < words.count {
                merged.append(word + "'" + words[i + 1])
                i += 2
            } else {
                merged.append(word)
                i += 1
            }
        }
        return merged
    }

    static func titleCased(_ name: String) -> String {
        let words = mergeStandaloneElisions(name.lowercased().split(separator: " "))
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

    /// Déduplique les noms bruts : d'abord les doublons exacts (ex. deux
    /// sites patrimoniaux distincts d'une même commune s'affichent tous les
    /// deux sous le simple nom de la commune, ex. "Lyon" en double dans le
    /// Rhône), puis, pour les musées uniquement (`mergeVariants`), les
    /// variantes où un nom est entièrement contenu dans un autre (ex.
    /// "Musée des Confluences" / "Muséum - Musée des Confluences") — on
    /// garde alors le plus court des deux, jugé le nom usuel.
    static func dedupedNames(_ names: [String], mergeVariants: Bool) -> [String] {
        var exactDeduped: [String] = []
        var seenTitleCased = Set<String>()
        for name in names {
            let key = titleCased(name)
            if seenTitleCased.insert(key).inserted { exactDeduped.append(name) }
        }
        guard mergeVariants else { return exactDeduped }

        var result: [String] = []
        for name in exactDeduped {
            let candidate = titleCased(name)
            if let existingIndex = result.firstIndex(where: { existing in
                let existingKey = titleCased(existing)
                return existingKey.localizedCaseInsensitiveContains(candidate) || candidate.localizedCaseInsensitiveContains(existingKey)
            }) {
                // Garde la variante la plus courte des deux.
                if name.count < result[existingIndex].count { result[existingIndex] = name }
            } else {
                result.append(name)
            }
        }
        return result
    }
}
