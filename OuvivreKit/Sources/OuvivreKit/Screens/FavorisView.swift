import SwiftUI

/// Favoris — tableau comparatif des départements mis en favori (étoile de
/// l'inspecteur), un département par colonne, la meilleure valeur de chaque
/// ligne étant mise en avant.
public struct FavorisView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState

    public init(derived: ClassicDerived) {}

    private let labelColW: CGFloat = 200
    /// Département dont la colonne est sélectionnée (clic sur la carte).
    @State private var selectedCode: String?
    /// Ordre des colonnes (codes INSEE), réordonnable par glisser-déposer
    /// sur les en-têtes et mémorisé entre les lancements. Les favoris absents
    /// de cette liste (ajoutés depuis) passent après, par code.
    @State private var columnOrder: [String] = UserDefaults.standard.stringArray(forKey: "favoriteColumnOrder") ?? []
    /// Largeur d'un caractère de la police mono 10 pt du nom de région.
    private let regionCharW: CGFloat = 6.02
    /// Colonne ajustée sur le nom de région le plus long, avec 1 caractère
    /// d'espacement de chaque côté.
    private var colW: CGFloat {
        let longest = departements.map { $0.nomRegion.count }.max() ?? 0
        return CGFloat(longest + 2) * regionCharW
    }

    private struct Cell { let text: String; let value: Double? }
    private struct Row: Identifiable {
        let id: String
        let label: String
        let cells: [Cell]
        /// `true` : la plus grande valeur est la meilleure ; `false` : la plus
        /// petite ; `nil` : pas de mise en avant (ligne informative).
        let higherIsBetter: Bool?
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
    private func moveColumn(_ code: String, before target: String) {
        var order = departements.map(\.codeInsee)
        guard code != target, let from = order.firstIndex(of: code), let to = order.firstIndex(of: target) else { return }
        order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        columnOrder = order
        UserDefaults.standard.set(order, forKey: "favoriteColumnOrder")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("FAVORIS", color: theme.accent).padding(.bottom, 16)
            if departements.isEmpty {
                Text("Aucun favori pour l'instant. Cliquez sur l'étoile d'un département dans l'inspecteur pour l'ajouter ici.")
                    .font(CFont.sans(15))
                    .foregroundStyle(ClassicTheme.sub)
                    .frame(maxWidth: 460, alignment: .leading)
            } else {
                Text("La meilleure valeur de chaque ligne est mise en avant. Les scores sont sur 100.")
                    .font(CFont.sans(15))
                    .foregroundStyle(ClassicTheme.sub)
                    .frame(maxWidth: 460, alignment: .leading)
                    .padding(.bottom, 24)
                ScrollView(.horizontal, showsIndicators: true) {
                    table.frame(minWidth: 700)
                }
                DepartementMapCard(
                    names: departements.map(\.nom),
                    accent: theme.accent,
                    selectedName: departements.first { $0.codeInsee == selectedCode }?.nom,
                    onSelect: { name in
                        let code = departements.first { $0.nom == name }?.codeInsee
                        selectedCode = selectedCode == code ? nil : code
                    },
                    height: 690
                )
                    .padding(.top, 32)
            }
        }
    }

    // MARK: - Données

    private var sections: [Section] {
        let deps = departements
        func score(_ text: (Double) -> String = { "\(Int($0.rounded()))" }, _ f: (FranceGeoData.DepartementScore) -> Double?) -> [Cell] {
            deps.map { d in f(d).map { Cell(text: text($0), value: $0) } ?? Cell(text: "—", value: nil) }
        }
        let geoLabels = ["paysEtranger": "Pays étranger", "mer": "Mer et océan", "montagne": "Montagne",
                         "lacs": "Lacs", "fleuves": "Fleuves et rivières", "forets": "Parcs et forêts"]
        let geoRows = FranceGeoData.criterionKeys.map { key in
            Row(id: "geo-\(key)", label: geoLabels[key] ?? key, cells: score { $0.scores[key] }, higherIsBetter: true)
        }
        let cultureRows: [Row] = [("musees", "Musées"), ("patrimoine", "Lieux du patrimoine"), ("festivals", "Festivals")].map { key, label in
            let cells = deps.map { d -> Cell in
                var n = CultureScores.names(forDepartementCode: d.codeInsee, criterionKey: key).count
                if key == "patrimoine" { n += CultureScores.names(forDepartementCode: d.codeInsee, criterionKey: "spr").count }
                return Cell(text: "\(n)", value: Double(n))
            }
            return Row(id: "culture-\(key)", label: label, cells: cells, higherIsBetter: true)
        }
        let meteo = deps.map { d -> (temp: Double?, rain: Double?) in
            // 12 derniers mois complets.
            let recent = MeteoMensuelle.series(forDepartementCode: d.codeInsee).filter { !$0.partial }.suffix(12)
            let temps = recent.compactMap(\.temperature)
            let rains = recent.compactMap(\.precipitation)
            return (temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count),
                    rains.isEmpty ? nil : rains.reduce(0, +))
        }
        let meteoRows = [
            Row(id: "meteo-temp", label: "Température moyenne", cells: meteo.map { m in
                m.temp.map { Cell(text: String(format: "%.1f °C", $0), value: $0) } ?? Cell(text: "—", value: nil)
            }, higherIsBetter: true),
            Row(id: "meteo-rain", label: "Précipitations", cells: meteo.map { m in
                m.rain.map { Cell(text: "\(Int($0.rounded())) mm", value: $0) } ?? Cell(text: "—", value: nil)
            }, higherIsBetter: false)
        ]
        return [
            Section(id: "geo", title: "GÉOGRAPHIE", rows: geoRows),
            Section(id: "culture", title: "CULTURE (nombre de lieux et d'événements)", rows: cultureRows),
            Section(id: "meteo", title: "MÉTÉO (valeurs sur les 12 derniers mois)", rows: meteoRows)
        ]
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

    // MARK: - Tableau

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("CRITÈRE").font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.faint)
                    .frame(width: labelColW, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 14)
                ForEach(departements, id: \.codeInsee) { d in
                    VStack(alignment: .center, spacing: 4) {
                        Text(d.nom).font(CFont.sans(13, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                        Text(d.nomRegion).font(CFont.mono(10)).foregroundStyle(ClassicTheme.faint)
                        HStack(spacing: 6) {
                            Button { state.toggleFavoriteDepartement(d.codeInsee) } label: {
                                Image(systemName: "star.fill").foregroundStyle(theme.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Retirer des favoris")
                            if topDepartementCodes.contains(d.codeInsee) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.accent)
                                    .help("Le plus de meilleures valeurs")
                            }
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(width: colW, alignment: .center)
                    .padding(.vertical, 12)
                    .background(d.codeInsee == selectedCode ? theme.accent.opacity(0.12) : .clear)
                    .overlay(Rectangle().fill(ClassicTheme.border).frame(width: 1), alignment: .leading)
                    .contentShape(Rectangle())
                    .draggable(d.codeInsee)
                    .dropDestination(for: String.self) { items, _ in
                        guard let code = items.first else { return false }
                        withAnimation(.easeInOut(duration: 0.2)) { moveColumn(code, before: d.codeInsee) }
                        return true
                    }
                    .help("Glisser pour réordonner les colonnes")
                }
            }
            .background(ClassicTheme.sidebarBg)
            .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.border).frame(height: 1) }

            ForEach(sections) { section in
                HStack(spacing: 0) {
                    Text(section.title).font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.faint)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ClassicTheme.cardAlt)
                .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }

                ForEach(section.rows) { row in
                    HStack(spacing: 0) {
                        Text(row.label).font(CFont.sans(13, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                            .frame(width: labelColW, alignment: .leading)
                            .padding(.horizontal, 18).padding(.vertical, 13)
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { i, c in
                            let best = isBest(c, in: row)
                            Text(c.text)
                                .font(CFont.sans(13, weight: best ? .semibold : .regular))
                                .foregroundStyle(best ? ClassicTheme.ink : ClassicTheme.sub)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .overlay { if best { RoundedRectangle(cornerRadius: 4).stroke(ClassicTheme.ink, lineWidth: 1) } }
                            .frame(width: colW, alignment: .center)
                            .padding(.vertical, 13)
                            .background(departements[i].codeInsee == selectedCode ? theme.accent.opacity(0.12) : .clear)
                            .overlay(Rectangle().fill(ClassicTheme.dividerLight).frame(width: 1), alignment: .leading)
                        }
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }
}
