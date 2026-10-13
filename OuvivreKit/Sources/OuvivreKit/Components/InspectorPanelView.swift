import SwiftUI
import Charts
import AppKit

/// Contenu de l'inspecteur du Sélecteur — panneau d'informations texte, sans
/// carte (la carte est affichée en plein cadre dans le panneau central, avec
/// ses propres boutons de contrôle dans la toolbar) : fiche du pays, puis
/// celle du département cliqué sur la carte.
struct InspectorPanelView: View {
    @EnvironmentObject var state: ClassicState
    @EnvironmentObject var mapState: MapPanelState
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }

    /// Département courant — `nil` tant qu'aucun département n'a de code
    /// résolu (`mapState.title` vaut "France" avant tout clic).
    private var departementCode: String? { FranceGeoData.byName[mapState.title]?.codeInsee }

    // Les catégories sont repliées par défaut : seules les clés dépliées
    // sont mémorisées, et remises à cet état initial à chaque nouveau
    // département.
    @State private var expandedKeys: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // `mapState.title` vaut "France" par défaut (avant tout
                // clic sur un département) — n'affiche la section
                // département que lorsqu'un vrai département est résolu,
                // sinon la fiche pays.
                if let code = departementCode {
                    departementHeader(code)

                    // Rubrique CULTURE : regroupe les sous-rubriques actives
                    // (Musées, Lieux du patrimoine, Festivals) ; l'icône ouvre
                    // la fenêtre qui les réunit toutes les trois.
                    if !state.activeCultureCriteria.isEmpty {
                        Divider()
                        HStack(spacing: 8) {
                            Eyebrow("Culture", color: c.faint, font: CFont.rounded(13, weight: .medium))
                            Spacer()
                            detailWindowButton(CultureDetailView.windowID, code: code)
                        }
                        .padding(.top, 4)
                        // 16 (VStack) + 4 (criterionSection) − 10 = 10 pt entre
                        // l'en-tête Culture et le premier critère, comme Météo.
                        .padding(.bottom, -10)
                    }

                    ForEach(state.activeCultureCriteria, id: \.key) { criterion in
                        criterionSection(criterion, code: code)
                    }

                    Divider()
                    meteoSection(code)
                } else {
                    countrySection
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: departementCode) { _, _ in expandedKeys = [] }
        // Aucun fond personnalisé — comme la sidebar (`.listStyle(.sidebar)`),
        // l'inspecteur s'appuie sur le matériau translucide natif du système
        // derrière son contenu plutôt qu'une couleur/opacité fixée ici.
    }

    private func departementHeader(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(code)
                    .font(CFont.rounded(20, weight: .bold))
                    .foregroundStyle(c.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(c.badge, in: RoundedRectangle(cornerRadius: 5))
                Text(mapState.title)
                    .font(CFont.rounded(20, weight: .bold))
                    .foregroundStyle(c.ink)
                Spacer(minLength: 8)
                let isFavorite = state.favoriteDepartementCodes.contains(code)
                Button {
                    state.toggleFavoriteDepartement(code)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(isFavorite ? ClassicTheme.favorite : c.faint)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
                // Ouvre la fenêtre du département (comme le double-clic dans la sidebar).
                Button {
                    openWindow(id: DepartementWindowView.windowID, value: code)
                } label: {
                    Image(systemName: "interface.window.on.rectangle")
                        .font(.system(size: 13))
                        .foregroundStyle(c.faint)
                }
                .buttonStyle(.plain)
                .help("Ouvrir la fenêtre du département")
            }
            if let chefLieu = FranceGeoData.chefsLieux[code] {
                HStack(spacing: 8) {
                    Text(chefLieu)
                        .font(CFont.rounded(18))
                        .foregroundStyle(c.faint)
                    Button {
                        // Recentre la carte sur la position du chef-lieu.
                        if let coordinate = FranceGeoData.chefsLieuxCoordinates[code] {
                            mapState.recenter(on: coordinate, span: 0.05)
                        }
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                            .font(CFont.rounded(13))
                            .foregroundStyle(c.faint)
                    }
                    .buttonStyle(.plain)
                    .help("Centrer la carte sur le chef-lieu")
                }
            }
        }
    }

    /// Icône ouvrant la fenêtre de détail (Culture ou Climat) du département.
    private func detailWindowButton(_ windowID: String, code: String) -> some View {
        Button {
            openWindow(id: windowID, value: code)
        } label: {
            Image(systemName: "interface.window.on.rectangle")
                .font(.system(size: 13))
                .foregroundStyle(c.faint)
        }
        .buttonStyle(.plain)
        .help("Ouvrir la vue détaillée")
    }

    /// « Climats dominants » : sans le nombre ni le tiret, un climat par ligne,
    /// avec une majuscule initiale (« 4 — océanique, semi-continental » →
    /// « Océanique\nSemi-continental »).
    private static func displayValue(_ f: LabeledValue) -> String {
        if f.key == "Population totale" { return f.value + " d'habitants" }
        guard f.key == "Climats dominants" else { return f.value }
        let parts = f.value.components(separatedBy: " — ")
        guard parts.count == 2 else { return f.value }
        return parts[1].components(separatedBy: ", ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "\n")
    }

    /// Fiche pays (nom + faits) déplacée ici depuis le bloc "Pays" du
    /// Sélecteur, qui ne garde que les capsules de choix.
    private var countrySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text([ClassicStatic.countryFlags[state.country], state.country].compactMap { $0 }.joined(separator: " "))
                .font(CFont.rounded(20, weight: .semibold))
                .foregroundStyle(c.ink)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(state.countryFacts) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.key == "Population totale" ? "Population" : f.key).font(CFont.rounded(13)).foregroundStyle(c.faint)
                        Text(Self.displayValue(f)).font(CFont.rounded(15, weight: .medium)).foregroundStyle(c.ink)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    /// Températures moyennes et précipitations mensuelles du département sur
    /// les 3 dernières années glissantes (5 ans dans la fenêtre détaillée),
    /// données Météo-France, moyenne des postes du département — voir
    /// `MeteoMensuelle`.
    private func meteoSection(_ code: String) -> some View {
        // L'inspecteur n'affiche que les 3 dernières années (la fenêtre
        // détaillée garde tout l'historique).
        let allSeries = MeteoMensuelle.series(forDepartementCode: code)
        let series: [MeteoMensuelle.Point] = allSeries.last.flatMap { last in
            Calendar.current.date(byAdding: .year, value: -3, to: last.date).map { cutoff in allSeries.filter { $0.date > cutoff } }
        } ?? allSeries
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Même en-tête que CULTURE (Eyebrow), sans chevron : la
                // rubrique Météo est toujours dépliée. L'icône ouvre la
                // fenêtre de détail (comme le double-clic).
                Eyebrow("Climat", color: c.faint, font: CFont.rounded(13, weight: .medium))
                Spacer()
                detailWindowButton(MeteoDetailView.windowID, code: code)
            }

            if series.isEmpty {
                Text("Aucune donnée pour ce département.")
                    .font(CFont.rounded(13))
                    .foregroundStyle(c.faint)
            } else {
                let yearBands = Self.yearBands(series).filter(\.alternate)
                meteoChart("Température moyenne (°C /mois)", unit: "°C", series: series, yearBands: yearBands, includesZero: false, value: \.temperature)
                meteoChart("Précipitations (mm / mois)", unit: "mm", series: series, yearBands: yearBands, includesZero: true, value: \.precipitation)
                    .padding(.top, 14)

                if series.last?.partial == true {
                    Text("Dernier mois en cours (données partielles).")
                        .font(CFont.rounded(11)).foregroundStyle(c.faint)
                }
            }
        }
        .padding(.top, 4)
        // Double-clic : détail dans une fenêtre séparée (scène déclarée par l'app).
        .simultaneousGesture(TapGesture(count: 2).onEnded { openWindow(id: MeteoDetailView.windowID, value: code) })
        .help("Double-clic pour ouvrir le détail dans une fenêtre")
    }

    /// Titre puis courbe mensuelle d'une grandeur, sur fond de bandes
    /// annuelles — courbe aussi pour les précipitations (test, au lieu de barres).
    @ViewBuilder
    private func meteoChart(_ title: String, unit: String, series: [MeteoMensuelle.Point], yearBands: [(start: Date, end: Date, alternate: Bool)], includesZero: Bool, value: KeyPath<MeteoMensuelle.Point, Double?>) -> some View {
        Text(title)
            .font(CFont.rounded(12)).foregroundStyle(c.ink)
        Chart {
            ForEach(yearBands, id: \.start) { band in
                RectangleMark(xStart: .value("Début", band.start), xEnd: .value("Fin", band.end))
                    .foregroundStyle(c.ink.opacity(0.05))
            }
            ForEach(series.filter { $0[keyPath: value] != nil }) { point in
                LineMark(x: .value("Mois", point.date, unit: .month), y: .value(unit, point[keyPath: value] ?? 0))
                    .foregroundStyle(ClassicTheme.accent)
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .year)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.year(), centered: false)
            }
        }
        .chartYScale(domain: .automatic(includesZero: includesZero))
        .frame(height: 110)
    }

    /// Une bande par année couverte par `series` — `alternate` vaut `true`
    /// une année sur deux (2ᵉ, 4ᵉ…), pour un fond légèrement opacifié en
    /// arrière-plan des graphiques Météo.
    private static func yearBands(_ series: [MeteoMensuelle.Point]) -> [(start: Date, end: Date, alternate: Bool)] {
        guard let first = series.first?.date, let last = series.last?.date else { return [] }
        let calendar = MeteoMensuelle.calendar
        let startYear = calendar.component(.year, from: first)
        let endYear = calendar.component(.year, from: last)
        guard startYear <= endYear else { return [] }
        return (startYear...endYear).enumerated().compactMap { index, year in
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
            return (start: start, end: end, alternate: index % 2 == 1)
        }
    }

    /// Le libellé du critère (repliable), suivi des noms des sites/événements
    /// de ce département pour ce critère (musées, festivals, ou communes du
    /// site patrimonial remarquable pour "Lieux du patrimoine").
    private func criterionSection(_ criterion: (label: String, key: String), code: String) -> some View {
        let names = CultureScores.dedupedNames(CultureScores.names(forDepartementCode: code, criterionKey: criterion.key), mergeVariants: criterion.key == "musees")
        let spr = criterion.key == "patrimoine" ? CultureScores.names(forDepartementCode: code, criterionKey: "spr") : []
        let isCollapsed = !expandedKeys.contains(criterion.key)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed { expandedKeys.insert(criterion.key) } else { expandedKeys.remove(criterion.key) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ClassicStatic.criterionIcons[criterion.label] ?? "checkmark.circle.fill")
                        .foregroundStyle(ClassicTheme.accent)
                    Text(criterion.label)
                        .font(CFont.rounded(12))
                        .foregroundStyle(c.ink)
                    Spacer()
                    Text("\(names.count + spr.count)")
                        .font(CFont.rounded(12))
                        .foregroundStyle(c.faint)
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c.faint)
                        .frame(width: 10)
                }
                // Chevron à droite du compteur, en retrait du bord droit.
                .padding(.trailing, 16)
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
                        .foregroundStyle(c.faint)
                } else if criterion.key == "musees" {
                    // Les Micro-Folies sont reléguées en fin de liste,
                    // séparées par un filet.
                    let microFolies = names.filter(CultureScores.isMicroFolie)
                    let regular = names.filter { !CultureScores.isMicroFolie($0) }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(regular, id: \.self) { name in
                            nameRow(name, criterionKey: criterion.key, code: code)
                        }
                        if !regular.isEmpty, !microFolies.isEmpty {
                            Divider().padding(.vertical, 4)
                        }
                        ForEach(microFolies, id: \.self) { name in
                            nameRow(name, criterionKey: criterion.key, code: code)
                        }
                    }
                } else if criterion.key == "festivals" {
                    // Regroupés par discipline dominante (les plus fournies
                    // d'abord), festivals sans discipline en dernier.
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(CultureScores.festivalsByDiscipline(forDepartementCode: code, names: names), id: \.discipline) { group in
                            VStack(alignment: .leading, spacing: 9) {
                                (Text(group.discipline.prefix(1).uppercased() + group.discipline.dropFirst().lowercased()).foregroundStyle(c.ink) + Text(" · \(group.names.count)").foregroundStyle(c.faint))
                                    .font(CFont.rounded(11, weight: .semibold))
                                    .padding(.top, 12)
                                ForEach(group.names, id: \.self) { name in
                                    nameRow(name, criterionKey: criterion.key, code: code)
                                }
                            }
                        }
                    }
                } else {
                    // Lazy : "Lieux du patrimoine" peut compter près de 2 000
                    // monuments historiques pour un seul département (Paris).
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(names, id: \.self) { name in
                            nameRow(name, criterionKey: criterion.key, code: code)
                        }
                        // Sites patrimoniaux remarquables (SPR) du département,
                        // après un filet — actif dès qu'"Important" ou
                        // "Déterminant" est réglé (la section n'existe que
                        // pour un critère au-dessus d'"Indifférent").
                        if !spr.isEmpty {
                            Divider().padding(.vertical, 6)
                            HStack(spacing: 6) {
                                Image(systemName: "eye")
                                    .font(CFont.rounded(11, weight: .semibold))
                                    .foregroundStyle(c.faint)
                                (Text("Sites patrimoniaux remarquables").foregroundStyle(c.ink) + Text(" · \(spr.count)").foregroundStyle(c.faint))
                                    .font(CFont.rounded(11, weight: .semibold))
                                Spacer()
                            }
                            .padding(.top, 12)
                            ForEach(spr, id: \.self) { name in
                                nameRow(name, criterionKey: "spr", code: code)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// Nom cliquable (curseur pointeur, mais pas de style lien visible sur
    /// le texte) — ouvre le site officiel ou une recherche web sur ce nom
    /// dans le navigateur par défaut (voir `CultureScores.link`).
    private func nameRow(_ name: String, criterionKey: String, code: String) -> some View {
        Button {
            if let url = CultureScores.link(forDepartementCode: code, criterionKey: criterionKey, name: name) { openURL(url) }
        } label: {
            Text(CultureScores.titleCased(name))
                .font(CFont.rounded(13))
                .lineSpacing(3)
                .foregroundStyle(c.body)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
