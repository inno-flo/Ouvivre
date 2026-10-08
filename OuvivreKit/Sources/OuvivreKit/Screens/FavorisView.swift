import SwiftUI
import AppKit

/// Favoris — tableau comparatif des départements mis en favori (étoile de
/// l'inspecteur), un département par colonne, la meilleure valeur de chaque
/// ligne étant mise en avant.
struct FavorisView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var pal: DetailColors { DetailColors(colorScheme) }
    @EnvironmentObject var state: ClassicState
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow

    /// Départements portant le badge `checkmark.seal.fill` parmi `codes` —
    /// utilisé par la sidebar (n'accède à aucun objet d'environnement).
    static func topDepartementCodes(among codes: Set<String>) -> Set<String> {
        topDepartementCodes(in: FranceGeoData.departements.filter { codes.contains($0.codeInsee) })
    }

    /// Police SF Pro Rounded mesurée pour ajuster les colonnes à leur texte.
    private static func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    /// Largeur de la colonne des critères : icône (18) + espace (8) + libellé le
    /// plus large, mesuré en SF Pro Rounded 13 medium — la cellule s'ajuste
    /// donc au texte (« Température maximale moyenne » tient sur une ligne).
    /// Les libellés étant fixes, elle n'est calculée qu'une fois.
    private static let labelColW: CGFloat = {
        let font = roundedFont(13, .medium)
        let widest = buildSections([]).flatMap(\.rows).map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(18 + 8 + widest)
    }()
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
    private static func colW(_ departements: [FranceGeoData.DepartementScore]) -> CGFloat {
        let nameFont = roundedFont(13, .semibold), regionFont = roundedFont(10, .regular)
        let candidates = departements.flatMap { d in
            [(d.nom, nameFont), (d.nomRegion, regionFont)]
        }.map { text, font in
            (width: (text as NSString).size(withAttributes: [.font: font]).width, count: max(text.count, 1))
        }
        guard let widest = candidates.max(by: { $0.width < $1.width }) else { return 0 }
        return ceil(widest.width + 2 * widest.width / CGFloat(widest.count))
    }

    /// Données du tableau, calculées une seule fois par rendu (et non à
    /// chaque cellule).
    private struct Model {
        /// Colonnes affichées : les départements qui ont le badge
        /// `checkmark.seal.fill` d'abord, chaque groupe gardant l'ordre de l'utilisateur.
        let departements: [FranceGeoData.DepartementScore]
        let sections: [Section]
        let topCodes: Set<String>
        let colW: CGFloat

        /// Largeur exacte du tableau : colonne Critère (avec ses marges) + colonnes
        /// des départements — il se resserre quand il y a moins de favoris.
        var tableWidth: CGFloat { FavorisView.labelColW + 36 + CGFloat(departements.count) * colW }
    }

    private var model: Model {
        let base = baseDepartements
        let top = Self.topDepartementCodes(in: base)
        let deps = base.filter { top.contains($0.codeInsee) } + base.filter { !top.contains($0.codeInsee) }
        return Model(departements: deps, sections: Self.buildSections(deps), topCodes: top, colW: Self.colW(deps))
    }

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

    /// Favoris dans l'ordre choisi par l'utilisateur (glisser-déposer).
    private var baseDepartements: [FranceGeoData.DepartementScore] {
        FranceGeoData.departements
            .filter { state.favoriteDepartementCodes.contains($0.codeInsee) }
            .sorted {
                let a = columnOrder.firstIndex(of: $0.codeInsee) ?? Int.max
                let b = columnOrder.firstIndex(of: $1.codeInsee) ?? Int.max
                return a != b ? a < b : $0.codeInsee < $1.codeInsee
            }
    }

    private func toggleSelection(_ code: String) {
        selectedCode = selectedCode == code ? nil : code
    }

    /// Place la colonne `code` à l'emplacement de la colonne `target`.
    private func moveColumn(_ code: String, before target: String) {
        var order = model.departements.map(\.codeInsee)
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

    var body: some View {
        let model = model
        let departements = model.departements
        VStack(alignment: .leading, spacing: 0) {
            if departements.isEmpty {
                Text("Aucun favori pour l'instant. Cliquez sur l'étoile d'un département dans l'inspecteur pour l'ajouter ici.")
                    .font(CFont.rounded(15))
                    .foregroundStyle(pal.sub)
                    .frame(maxWidth: 460, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    table(model).frame(width: model.tableWidth)
                }
                DepartementMapCard(
                    names: departements.map(\.nom),
                    selectedName: departements.first { $0.codeInsee == selectedCode }?.nom,
                    onSelect: { name in
                        if let code = FranceGeoData.byName[name]?.codeInsee { toggleSelection(code) }
                    },
                    height: 862
                )
                    .padding(.top, 32)
            }
        }
        .alert("Retirer \(pendingRemovalName) des favoris", isPresented: Binding(
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
        pendingRemovalCode.map(FranceGeoData.nom(forCode:)) ?? ""
    }

    // MARK: - Données

    private static func buildSections(_ deps: [FranceGeoData.DepartementScore]) -> [Section] {
        func score(_ f: (FranceGeoData.DepartementScore) -> Double?) -> [Cell] {
            deps.map { d in f(d).map { Cell(text: "\(Int($0.rounded()))", value: $0) } ?? Cell(text: "—", value: nil) }
        }
        let geoRows = zip(FranceGeoData.criterionKeys, ClassicStatic.geo).map { key, label in
            Row(id: "geo-\(key)", label: label, cells: score { $0.scores[key] }, higherIsBetter: true)
        }
        let cultureRows: [Row] = zip(CultureScores.criterionKeys, ClassicStatic.culture).map { key, label in
            let cells = deps.map { d -> Cell in
                var n = CultureScores.names(forDepartementCode: d.codeInsee, criterionKey: key).count
                if key == "patrimoine" { n += CultureScores.names(forDepartementCode: d.codeInsee, criterionKey: "spr").count }
                return Cell(text: frThousands(n), value: Double(n))
            }
            return Row(id: "culture-\(key)", label: label, cells: cells, higherIsBetter: true)
        }
        let meteo = deps.map { d -> (temp: Double?, tmax: Double?, record: Double?, rain: Double?) in
            // 12 derniers mois complets.
            let recent = MeteoMensuelle.series(forDepartementCode: d.codeInsee).filter { !$0.partial }.suffix(12)
            let temps = recent.compactMap(\.temperature)
            let maxes = recent.compactMap(\.maxTemperature)
            let records = recent.compactMap(\.absoluteMax)
            let rains = recent.compactMap(\.precipitation)
            return (temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count),
                    maxes.isEmpty ? nil : maxes.reduce(0, +) / Double(maxes.count),
                    records.max(),
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
            // Maximum absolu relevé dans le département sur les 12 mois.
            Row(id: "meteo-record", label: "Record de température", cells: meteo.map { m in
                m.record.map { Cell(text: frDecimal($0) + " °C", value: $0) } ?? Cell(text: "—", value: nil)
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
            Section(id: "meteo", title: "Climat (valeurs calculées sur les 12 derniers mois)", rows: meteoRows)
        ]
    }

    /// Couleur du filet entourant une valeur, `nil` si elle n'est pas entourée.
    private func outline(_ cell: Cell, in row: Row) -> Color? {
        if row.extremes {
            let values = row.cells.compactMap(\.value)
            guard let v = cell.value, let hi = values.max(), let lo = values.min(), hi != lo else { return nil }
            return v == hi ? .red : v == lo ? Color(red: 0.35, green: 0.70, blue: 0.95) : nil
        }
        return Self.isBest(cell, in: row) ? pal.ink : nil
    }

    /// Icône en face de la plus haute / plus basse valeur d'une ligne à icônes.
    private func icon(_ cell: Cell, in row: Row) -> String? {
        guard let icons = row.extremeIcons, let v = cell.value else { return nil }
        let values = row.cells.compactMap(\.value)
        guard let hi = values.max(), let lo = values.min(), hi != lo else { return nil }
        return v == hi ? icons.high : v == lo ? icons.low : nil
    }

    private static func isBest(_ cell: Cell, in row: Row) -> Bool {
        guard let higher = row.higherIsBetter, let v = cell.value else { return false }
        let values = row.cells.compactMap(\.value)
        guard values.count > 1, let best = higher ? values.max() : values.min(), let worst = higher ? values.min() : values.max(), best != worst else { return false }
        return v == best
    }

    /// Codes des départements ayant le plus de valeurs mises en avant (tous
    /// ceux à égalité, tant que ce maximum est supérieur à 0).
    private static func topDepartementCodes(in deps: [FranceGeoData.DepartementScore]) -> Set<String> {
        var counts = Array(repeating: 0, count: deps.count)
        for row in buildSections(deps).flatMap(\.rows) {
            for (i, cell) in row.cells.enumerated() where isBest(cell, in: row) { counts[i] += 1 }
        }
        guard let top = counts.max(), top > 0 else { return [] }
        return Set(zip(deps, counts).filter { $0.1 == top }.map(\.0.codeInsee))
    }

    // MARK: - Éléments de colonne

    private func headerContent(_ d: FranceGeoData.DepartementScore, isTop: Bool) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(d.nom).font(CFont.rounded(13, weight: .semibold)).foregroundStyle(pal.body)
            Text(d.nomRegion).font(CFont.rounded(10)).foregroundStyle(pal.sub)
            HStack(spacing: 6) {
                Button { pendingRemovalCode = d.codeInsee } label: {
                    Image(systemName: "star.fill").foregroundStyle(ClassicTheme.favorite)
                }
                .buttonStyle(.plain)
                .help("Retirer des favoris")
                if isTop {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(ClassicTheme.favorite)
                        .help("Le plus de meilleures valeurs")
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    /// Hauteur de contenu commune au libellé de critère et aux valeurs : elle
    /// fixe la hauteur de toutes les rangées, quelle que soit la hauteur
    /// propre du texte ou de l'icône SF Symbol (qui varie d'un symbole à l'autre).
    private static let rowContentHeight: CGFloat = 22

    private func valueLabel(_ c: Cell, outline: Color?, icon: String? = nil) -> some View {
        // Test : les valeurs mises en évidence ont le style des valeurs normales.
        return Text(c.text)
            .font(CFont.rounded(13, weight: .medium))
            .foregroundStyle(pal.sub)
            .padding(.horizontal, 8)
            .frame(height: Self.rowContentHeight)
            .overlay { if let outline { RoundedRectangle(cornerRadius: 4).stroke(outline, lineWidth: 1) } }
            // À gauche de la valeur, sans la décentrer.
            .overlay(alignment: .leading) {
                if let icon { Image(systemName: icon).font(.system(size: 13)).foregroundStyle(pal.sub).offset(x: -22) }
            }
    }

    /// Aperçu suivant le curseur pendant le glissement : toute la colonne
    /// (en-tête, intitulés de rubrique vides et valeurs), en transparence.
    private func columnPreview(_ d: FranceGeoData.DepartementScore, index: Int, model: Model) -> some View {
        let colW = model.colW
        return VStack(spacing: 0) {
            headerContent(d, isTop: model.topCodes.contains(d.codeInsee))
                .frame(width: colW).padding(.vertical, 12)
                .background(pal.window)
                .overlay(alignment: .bottom) { Rectangle().fill(pal.border).frame(height: 1) }
            ForEach(model.sections) { section in
                if !section.title.isEmpty {
                    Text(" ").font(CFont.rounded(13, weight: .medium))
                        .padding(.vertical, 8)
                        .frame(width: colW)
                        .background(pal.track.opacity(0.45))
                        .overlay(alignment: .bottom) { Rectangle().fill(pal.divider).frame(height: 1) }
                }
                ForEach(section.rows) { row in
                    valueLabel(row.cells[index], outline: outline(row.cells[index], in: row), icon: icon(row.cells[index], in: row))
                        .frame(width: colW).padding(.vertical, 13)
                        .overlay(alignment: .bottom) { Rectangle().fill(pal.divider).frame(height: 1) }
                }
            }
        }
        .background(pal.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.border, lineWidth: 1))
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
                    .foregroundStyle(pal.faint)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.id == "meteo-temp" ? "Ouvrir la fenêtre détaillée du Climat" : "Ouvrir les données culturelles dans une fenêtre")
        }
    }

    /// Lignes dont le séparateur est un filet court centré dans chaque
    /// colonne : Musées, Lieux du patrimoine, Températures moyenne et maximale.
    private static let shortSeparatorRowIDs: Set<String> = ["culture-musees", "culture-patrimoine", "meteo-temp", "meteo-tmax", "meteo-record"]

    // MARK: - Tableau

    private func table(_ model: Model) -> some View {
        let departements = model.departements, colW = model.colW
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: Self.labelColW, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 14)
                ForEach(Array(departements.enumerated()), id: \.element.codeInsee) { index, d in
                    headerContent(d, isTop: model.topCodes.contains(d.codeInsee))
                    .frame(width: colW, alignment: .center)
                    .padding(.vertical, 12)
                    .background(d.codeInsee == selectedCode ? ClassicTheme.accent.opacity(0.12) : Color.clear)
                    .overlay(Rectangle().fill(pal.border).frame(width: 1), alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(draggingCode == d.codeInsee ? 0.5 : 1)
                    .onTapGesture { toggleSelection(d.codeInsee) }
                    .onDrag {
                        draggingCode = d.codeInsee
                        return NSItemProvider(object: d.codeInsee as NSString)
                    } preview: {
                        columnPreview(d, index: index, model: model)
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
            .overlay(alignment: .bottom) { Rectangle().fill(pal.border).frame(height: 1) }
            // `.compositingGroup()` : sans lui, le fond de cette ligne
            // (contenant plusieurs cellules avec leurs propres gestes de
            // glisser-déposer) pouvait n'être composé que partiellement par
            // le moteur de rendu dans la ScrollView horizontale, laissant
            // une bande blanche en bas de la ligne dès l'ouverture de l'écran.
            .compositingGroup()

            ForEach(model.sections) { section in
                if !section.title.isEmpty {
                    HStack(spacing: 0) {
                        Eyebrow(section.title, color: pal.faint, font: CFont.rounded(13, weight: .medium), tracking: 1)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(pal.track.opacity(0.45))
                    .overlay(alignment: .bottom) { Rectangle().fill(pal.divider).frame(height: 1) }
                    .compositingGroup()
                }

                ForEach(section.rows) { row in
                    HStack(alignment: .center, spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: ClassicStatic.criterionIcons[row.label] ?? "circle").frame(width: 18, height: Self.rowContentHeight)
                                .foregroundStyle(ClassicTheme.accent)
                            Text(row.label).font(CFont.rounded(13, weight: .medium)).foregroundStyle(pal.body)
                        }
                            .frame(height: Self.rowContentHeight)
                            .frame(width: Self.labelColW, alignment: .leading)
                            .padding(.horizontal, 18).padding(.vertical, 13)
                            .overlay(alignment: .bottom) {
                                // Entre deux critères d'une même rubrique : filet
                                // court et centré plutôt que pleine largeur.
                                Rectangle().fill(pal.divider).frame(height: 1)
                                    .padding(.horizontal, Self.shortSeparatorRowIDs.contains(row.id) ? 56 : 0)
                            }
                        ForEach(Array(departements.enumerated()), id: \.element.codeInsee) { i, d in
                            let c = row.cells[i]
                            valueLabel(c, outline: outline(c, in: row), icon: icon(c, in: row))
                            .frame(width: colW, alignment: .center)
                            .padding(.vertical, 13)
                            // Étire la cellule sur toute la hauteur de la ligne
                            // (celle de la cellule titre, qui la détermine) —
                            // sinon, quand le libellé passe sur deux lignes
                            // (« Température maximale moyenne »), la cellule
                            // de valeur restait à sa hauteur intrinsèque plus
                            // courte et son filet de séparation flottait au
                            // milieu de la ligne au lieu de longer sa base.
                            .frame(maxHeight: .infinity)
                            .background(d.codeInsee == selectedCode ? ClassicTheme.accent.opacity(0.12) : .clear)
                            .opacity(draggingCode == d.codeInsee ? 0.5 : 1)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleSelection(d.codeInsee) }
                            .overlay(Rectangle().fill(pal.divider).frame(width: 1), alignment: .leading)
                            .overlay(alignment: .topTrailing) { detailButton(row: row, code: d.codeInsee) }
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(pal.divider).frame(height: 1)
                                    .padding(.horizontal, Self.shortSeparatorRowIDs.contains(row.id) ? 28 : 0)
                            }
                        }
                    }
                }
            }
        }
        .background(pal.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.border, lineWidth: 1))
    }
}
