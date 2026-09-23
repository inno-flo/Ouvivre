import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Favoris — tableau comparatif des départements mis en favori (étoile de
/// l'inspecteur), un département par colonne, la meilleure valeur de chaque
/// ligne étant mise en avant.
public struct FavorisView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow

    public init(derived: ClassicDerived) {}

    private let labelColW: CGFloat = 200
    /// Département dont la colonne est sélectionnée (clic sur la carte).
    @State private var selectedCode: String?
    /// Ordre des colonnes (codes INSEE), réordonnable par glisser-déposer
    /// sur les en-têtes et mémorisé entre les lancements. Les favoris absents
    /// de cette liste (ajoutés depuis) passent après, par code.
    @State private var columnOrder: [String] = UserDefaults.standard.stringArray(forKey: "favoriteColumnOrder") ?? []
    /// Colonne en cours de glissement : les autres s'écartent en direct pour
    /// montrer l'emplacement de dépôt.
    @State private var draggingCode: String?
    /// Département dont le retrait des favoris attend confirmation.
    @State private var pendingRemovalCode: String?
    /// Largeur mesurée (SF Pro Rounded) du texte le plus large de l'en-tête —
    /// nom de département (13 semibold) ou de région (10) —, plus 1 caractère
    /// moyen d'espacement de chaque côté.
    private var colW: CGFloat {
        #if canImport(AppKit)
        func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
        let nameFont = rounded(13, .semibold), regionFont = rounded(10, .regular)
        let candidates = departements.flatMap { d in
            [(d.nom, nameFont), (d.nomRegion, regionFont)]
        }.map { text, font in
            (width: (text as NSString).size(withAttributes: [.font: font]).width, count: max(text.count, 1))
        }
        guard let widest = candidates.max(by: { $0.width < $1.width }) else { return 0 }
        return ceil(widest.width + 2 * widest.width / CGFloat(widest.count))
        #else
        let longest = departements.flatMap { [$0.nom.count, $0.nomRegion.count] }.max() ?? 0
        return CGFloat(longest + 2) * 7
        #endif
    }

    /// Largeur exacte du tableau : colonne Critère (avec ses marges) + colonnes
    /// des départements — il se resserre quand il y a moins de favoris.
    private var tableWidth: CGFloat { labelColW + 36 + CGFloat(departements.count) * colW }


    private struct Cell { let text: String; let value: Double? }
    private struct Row: Identifiable {
        let id: String
        let label: String
        let cells: [Cell]
        /// `true` : la plus grande valeur est la meilleure ; `false` : la plus
        /// petite ; `nil` : pas de mise en avant (ligne informative).
        let higherIsBetter: Bool?
        /// Ligne dont seuls les extrêmes sont entourés : la plus haute valeur en
        /// rouge, la plus basse en bleu ciel.
        var extremes: Bool = false
        /// Icônes affichées en face de la plus haute / de la plus basse valeur.
        var extremeIcons: (high: String, low: String)?
    }
    private struct Section: Identifiable {
        let id: String
        let title: String
        let rows: [Row]
    }

    private var departements: [FranceGeoData.DepartementScore] {
        FranceGeoData.departements
            .filter { state.favoriteDepartementCodes.contains($0.codeInsee) }
            .sorted {
                let a = columnOrder.firstIndex(of: $0.codeInsee) ?? Int.max
                let b = columnOrder.firstIndex(of: $1.codeInsee) ?? Int.max
                return a != b ? a < b : $0.codeInsee < $1.codeInsee
            }
    }

    /// Place la colonne `code` à l'emplacement de la colonne `target`.
    private func toggleSelection(_ code: String) {
        selectedCode = selectedCode == code ? nil : code
    }

    private func moveColumn(_ code: String, before target: String) {
        var order = departements.map(\.codeInsee)
        guard code != target, let from = order.firstIndex(of: code), let to = order.firstIndex(of: target) else { return }
        order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        columnOrder = order
    }

    private struct ColumnDropDelegate: DropDelegate {
        let target: String
        @Binding var dragging: String?
        let move: (String, String) -> Void
        let commit: () -> Void

        func dropEntered(info: DropInfo) {
            guard let dragging, dragging != target else { return }
            withAnimation(.easeInOut(duration: 0.25)) { move(dragging, target) }
        }
        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
        func performDrop(info: DropInfo) -> Bool {
            dragging = nil
            commit()
            return true
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if departements.isEmpty {
                Text("Aucun favori pour l'instant. Cliquez sur l'étoile d'un département dans l'inspecteur pour l'ajouter ici.")
                    .font(CFont.rounded(15))
                    .foregroundStyle(ClassicTheme.sub)
                    .frame(maxWidth: 460, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    table.frame(width: tableWidth)
                }
                DepartementMapCard(
                    names: departements.map(\.nom),
                    accent: theme.accent,
                    selectedName: departements.first { $0.codeInsee == selectedCode }?.nom,
                    onSelect: { name in
                        let code = departements.first { $0.nom == name }?.codeInsee
                        if let code { toggleSelection(code) }
                    },
                    height: 862,
                    actionsFirst: true,
                    roundedFont: true
                )
                    .padding(.top, 32)
            }
        }
        .alert("Retirer \(pendingRemovalName) des favoris ?", isPresented: Binding(
            get: { pendingRemovalCode != nil },
            set: { if !$0 { pendingRemovalCode = nil } }
        )) {
            Button("Retirer", role: .destructive) {
                if let code = pendingRemovalCode {
                    withAnimation { state.setFavorite(code, isOn: false, undoManager: undoManager) }
                }
                pendingRemovalCode = nil
            }
            Button("Annuler", role: .cancel) { pendingRemovalCode = nil }
        } message: {
            Text("Ce département disparaîtra du comparatif. Vous pourrez le rajouter avec l'étoile de l'inspecteur.")
        }
    }

    private var pendingRemovalName: String {
        FranceGeoData.departements.first { $0.codeInsee == pendingRemovalCode }?.nom ?? ""
    }

    // MARK: - Données

    private var sections: [Section] {
        let deps = departements
        func score(_ text: (Double) -> String = { "\(Int($0.rounded()))" }, _ f: (FranceGeoData.DepartementScore) -> Double?) -> [Cell] {
            deps.map { d in f(d).map { Cell(text: text($0), value: $0) } ?? Cell(text: "—", value: nil) }
        }
        let geoLabels = ["paysEtranger": "Pays étranger", "mer": "Mer ou océan", "montagne": "Montagne",
                         "lacs": "Lacs", "fleuves": "Fleuves et rivières", "forets": "Parcs et forêts"]
        let geoRows = FranceGeoData.criterionKeys.map { key in
            Row(id: "geo-\(key)", label: geoLabels[key] ?? key, cells: score { $0.scores[key] }, higherIsBetter: true)
        }
        let cultureRows: [Row] = [("musees", "Musées"), ("patrimoine", "Lieux du patrimoine"), ("festivals", "Festivals")].map { key, label in
            let cells = deps.map { d -> Cell in
                var n = CultureScores.names(forDepartementCode: d.codeInsee, criterionKey: key).count
                if key == "patrimoine" { n += CultureScores.names(forDepartementCode: d.codeInsee, criterionKey: "spr").count }
                return Cell(text: frThousands(n), value: Double(n))
            }
            return Row(id: "culture-\(key)", label: label, cells: cells, higherIsBetter: true)
        }
        let meteo = deps.map { d -> (temp: Double?, tmax: Double?, rain: Double?) in
            // 12 derniers mois complets.
            let recent = MeteoMensuelle.series(forDepartementCode: d.codeInsee).filter { !$0.partial }.suffix(12)
            let temps = recent.compactMap(\.temperature)
            let maxes = recent.compactMap(\.maxTemperature)
            let rains = recent.compactMap(\.precipitation)
            return (temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count),
                    maxes.isEmpty ? nil : maxes.reduce(0, +) / Double(maxes.count),
                    rains.isEmpty ? nil : rains.reduce(0, +))
        }
        let meteoRows = [
            Row(id: "meteo-temp", label: "Température moyenne", cells: meteo.map { m in
                m.temp.map { Cell(text: frDecimal($0) + " °C", value: $0) } ?? Cell(text: "—", value: nil)
            }, higherIsBetter: nil, extremes: true),
            // Moyenne des températures maximales quotidiennes de chaque mois.
            Row(id: "meteo-tmax", label: "Température maximale moyenne", cells: meteo.map { m in
                m.tmax.map { Cell(text: frDecimal($0) + " °C", value: $0) } ?? Cell(text: "—", value: nil)
            }, higherIsBetter: nil, extremes: true),
            Row(id: "meteo-rain", label: "Précipitations annuelles", cells: meteo.map { m in
                m.rain.map { Cell(text: "\(frThousands(Int($0.rounded()))) mm", value: $0) } ?? Cell(text: "—", value: nil)
            }, higherIsBetter: nil, extremeIcons: (high: "cloud.heavyrain.fill", low: "cloud.drizzle"))
        ]
        return [
            Section(id: "chefLieu", title: "", rows: [
                Row(id: "chefLieu", label: "Chef-lieu", cells: deps.map { Cell(text: FranceGeoData.chefsLieux[$0.codeInsee] ?? "—", value: nil) }, higherIsBetter: nil)
            ]),
            Section(id: "geo", title: "Géographie (les scores de correspondance entre le département et les critères de choix sont sur 100)", rows: geoRows),
            Section(id: "culture", title: "Culture (nombre de lieux et d'événements)", rows: cultureRows),
            Section(id: "meteo", title: "Météo (valeurs calculées sur les 12 derniers mois)", rows: meteoRows)
        ]
    }

    /// Couleur du filet entourant une valeur, `nil` si elle n'est pas entourée.
    private func outline(_ cell: Cell, in row: Row) -> Color? {
        if row.extremes {
            let values = row.cells.compactMap(\.value)
            guard let v = cell.value, let hi = values.max(), let lo = values.min(), hi != lo else { return nil }
            return v == hi ? .red : v == lo ? Color(red: 0.35, green: 0.70, blue: 0.95) : nil
        }
        return isBest(cell, in: row) ? ClassicTheme.ink : nil
    }

    /// Icône en face de la plus haute / plus basse valeur d'une ligne à icônes.
    private func icon(_ cell: Cell, in row: Row) -> String? {
        guard let icons = row.extremeIcons, let v = cell.value else { return nil }
        let values = row.cells.compactMap(\.value)
        guard let hi = values.max(), let lo = values.min(), hi != lo else { return nil }
        return v == hi ? icons.high : v == lo ? icons.low : nil
    }

    private func isBest(_ cell: Cell, in row: Row) -> Bool {
        guard let higher = row.higherIsBetter, let v = cell.value else { return false }
        let values = row.cells.compactMap(\.value)
        guard values.count > 1, let best = higher ? values.max() : values.min(), let worst = higher ? values.min() : values.max(), best != worst else { return false }
        return v == best
    }

    /// Codes des départements ayant le plus de valeurs mises en avant (tous
    /// ceux à égalité, tant que ce maximum est supérieur à 0).
    private var topDepartementCodes: Set<String> {
        let deps = departements
        var counts = Array(repeating: 0, count: deps.count)
        for row in sections.flatMap(\.rows) {
            for (i, cell) in row.cells.enumerated() where isBest(cell, in: row) { counts[i] += 1 }
        }
        guard let top = counts.max(), top > 0 else { return [] }
        return Set(zip(deps, counts).filter { $0.1 == top }.map(\.0.codeInsee))
    }


    // MARK: - Éléments de colonne

    private func headerContent(_ d: FranceGeoData.DepartementScore) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(d.nom).font(CFont.rounded(13, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
            Text(d.nomRegion).font(CFont.rounded(10)).foregroundStyle(ClassicTheme.faint)
            HStack(spacing: 6) {
                Button { pendingRemovalCode = d.codeInsee } label: {
                    Image(systemName: "star.fill").foregroundStyle(ClassicTheme.favorite)
                }
                .buttonStyle(.plain)
                .help("Retirer des favoris")
                if topDepartementCodes.contains(d.codeInsee) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(ClassicTheme.favorite)
                        .help("Le plus de meilleures valeurs")
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    private func valueLabel(_ c: Cell, outline: Color?, icon: String? = nil) -> some View {
        let highlighted = outline != nil
        // Poids fixe (medium), identique à celui du libellé de critère —
        // faire varier le poids selon `highlighted` donnait des hauteurs de
        // texte légèrement différentes d'une ligne à l'autre, malgré une
        // taille de police unique de 13 pt partout dans le tableau.
        return Text(c.text)
            .font(CFont.rounded(13, weight: .medium))
            .foregroundStyle(highlighted ? ClassicTheme.ink : ClassicTheme.sub)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay { if let outline { RoundedRectangle(cornerRadius: 4).stroke(outline, lineWidth: 1) } }
            // À gauche de la valeur, sans la décentrer.
            .overlay(alignment: .leading) {
                if let icon { Image(systemName: icon).font(.system(size: 13)).foregroundStyle(ClassicTheme.sub).offset(x: -22) }
            }
    }

    /// Aperçu suivant le curseur pendant le glissement : toute la colonne
    /// (en-tête, intitulés de rubrique vides et valeurs), en transparence.
    private func columnPreview(_ d: FranceGeoData.DepartementScore) -> some View {
        let index = departements.firstIndex { $0.codeInsee == d.codeInsee } ?? 0
        return VStack(spacing: 0) {
            headerContent(d)
                .frame(width: colW).padding(.vertical, 12)
                .background(Color(hex: 0xF4F2EE))
                .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.border).frame(height: 1) }
            ForEach(sections) { section in
                if !section.title.isEmpty {
                    Text(" ").font(CFont.rounded(13, weight: .medium))
                        .padding(.vertical, 8)
                        .frame(width: colW)
                        .background(.white)
                        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                }
                ForEach(section.rows) { row in
                    valueLabel(row.cells[index], outline: outline(row.cells[index], in: row), icon: icon(row.cells[index], in: row))
                        .frame(width: colW).padding(.vertical, 13)
                        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClassicTheme.border, lineWidth: 1))
        .opacity(0.6)
    }

    /// Icône en haut à droite de la cellule Musées / Température moyenne : ouvre
    /// la fenêtre de détail Culture / Météo du département de la colonne.
    @ViewBuilder
    private func detailButton(row: Row, code: String) -> some View {
        let windowID: String? = switch row.id {
        case "culture-musees": CultureDetailView.windowID
        case "meteo-temp": MeteoDetailView.windowID
        default: nil
        }
        if let windowID {
            Button { openWindow(id: windowID, value: code) } label: {
                Image(systemName: "interface.window.on.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(ClassicTheme.faint)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.id == "meteo-temp" ? "Ouvrir le détail Météo dans une fenêtre" : "Ouvrir les données culturelles dans une fenêtre")
        }
    }

    /// Lignes dont le séparateur est un filet court centré dans chaque
    /// colonne : Musées, Lieux du patrimoine, Températures moyenne et maximale.
    private static let shortSeparatorRowIDs: Set<String> = ["culture-musees", "culture-patrimoine", "meteo-temp", "meteo-tmax"]

    // MARK: - Tableau

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: labelColW, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 14)
                ForEach(departements, id: \.codeInsee) { d in
                    headerContent(d)
                    .frame(width: colW, alignment: .center)
                    .padding(.vertical, 12)
                    .background(d.codeInsee == selectedCode ? theme.accent.opacity(0.12) : .clear)
                    .overlay(Rectangle().fill(ClassicTheme.border).frame(width: 1), alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(draggingCode == d.codeInsee ? 0.5 : 1)
                    .onTapGesture { toggleSelection(d.codeInsee) }
                    .onDrag {
                        draggingCode = d.codeInsee
                        return NSItemProvider(object: d.codeInsee as NSString)
                    } preview: {
                        columnPreview(d)
                    }
                    .onDrop(of: [.text], delegate: ColumnDropDelegate(
                        target: d.codeInsee,
                        dragging: $draggingCode,
                        move: moveColumn,
                        commit: { UserDefaults.standard.set(columnOrder, forKey: "favoriteColumnOrder") }
                    ))
                    .help("Glisser pour réordonner les colonnes")
                }
            }
            .background(Color(hex: 0xF4F2EE))
            .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.border).frame(height: 1) }
            // `.compositingGroup()` : sans lui, le fond de cette ligne
            // (contenant plusieurs cellules avec leurs propres gestes de
            // glisser-déposer) pouvait n'être composé que partiellement par
            // le moteur de rendu dans la ScrollView horizontale, laissant
            // une bande blanche en bas de la ligne dès l'ouverture de l'écran.
            .compositingGroup()

            ForEach(sections) { section in
                if !section.title.isEmpty {
                HStack(spacing: 0) {
                    Eyebrow(section.title, color: ClassicTheme.faint, font: CFont.rounded(13, weight: .medium), tracking: 1)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white)
                .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                .compositingGroup()
                }

                ForEach(section.rows) { row in
                    // Ligne de base plutôt que centrage : les poids de police
                    // différents entre le libellé (medium) et les valeurs
                    // (regular/semibold) ont des hauteurs de texte légèrement
                    // différentes même avec un padding identique, ce qui
                    // laissait un décalage résiduel d'un pixel ou deux.
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: ClassicStatic.criterionIcons[row.label] ?? "circle").frame(width: 18)
                                .foregroundStyle(theme.accent)
                            Text(row.label).font(CFont.rounded(13, weight: .medium)).foregroundStyle(ClassicTheme.body)
                        }
                            // Même hauteur de cellule que les colonnes de valeurs
                            // (`valueLabel` a ce même padding vertical de 3 pt) —
                            // sans lui, SwiftUI centrait la cellule label, plus
                            // courte, dans la hauteur de la ligne, ce qui
                            // décalait son contenu de quelques pixels vers le
                            // haut par rapport aux colonnes de départements.
                            .padding(.vertical, 3)
                            .frame(width: labelColW, alignment: .leading)
                            .padding(.horizontal, 18).padding(.vertical, 13)
                            .overlay(alignment: .bottom) {
                                // Entre deux critères d'une même rubrique : filet
                                // court et centré plutôt que pleine largeur.
                                Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1)
                                    .padding(.horizontal, Self.shortSeparatorRowIDs.contains(row.id) ? 56 : 0)
                            }
                        ForEach(Array(departements.enumerated()), id: \.element.codeInsee) { i, d in
                            let c = row.cells[i]
                            valueLabel(c, outline: outline(c, in: row), icon: icon(c, in: row))
                            .frame(width: colW, alignment: .center)
                            .padding(.vertical, 13)
                            .background(d.codeInsee == selectedCode ? theme.accent.opacity(0.12) : .clear)
                            .opacity(draggingCode == d.codeInsee ? 0.5 : 1)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleSelection(d.codeInsee) }
                            .overlay(Rectangle().fill(ClassicTheme.dividerLight).frame(width: 1), alignment: .leading)
                            .overlay(alignment: .topTrailing) { detailButton(row: row, code: d.codeInsee) }
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1)
                                    .padding(.horizontal, Self.shortSeparatorRowIDs.contains(row.id) ? 28 : 0)
                            }
                        }
                    }
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }
}
