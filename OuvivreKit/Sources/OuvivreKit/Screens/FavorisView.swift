import SwiftUI

/// Favoris — tableau comparatif des départements mis en favori (étoile de
/// l'inspecteur), un département par colonne, la meilleure valeur de chaque
/// ligne étant mise en avant.
public struct FavorisView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState

    public init(derived: ClassicDerived) {}

    private let labelColW: CGFloat = 200
    private let colW: CGFloat = 170

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
            .sorted { $0.codeInsee < $1.codeInsee }
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
                Text("PAR DÉPARTEMENT").font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.faint)
                    .padding(.top, 32).padding(.bottom, 12)
                ScrollView(.horizontal, showsIndicators: true) {
                    transposedTable
                }
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
            Row(id: "meteo-rain", label: "Précipitations / an", cells: meteo.map { m in
                m.rain.map { Cell(text: "\(Int($0.rounded())) mm", value: $0) } ?? Cell(text: "—", value: nil)
            }, higherIsBetter: false)
        ]
        return [
            Section(id: "geo", title: "GÉOGRAPHIE", rows: geoRows),
            Section(id: "culture", title: "CULTURE", rows: cultureRows),
            Section(id: "meteo", title: "MÉTÉO (12 DERNIERS MOIS)", rows: meteoRows)
        ]
    }

    private func isBest(_ cell: Cell, in row: Row) -> Bool {
        guard let higher = row.higherIsBetter, let v = cell.value else { return false }
        let values = row.cells.compactMap(\.value)
        guard values.count > 1, let best = higher ? values.max() : values.min(), let worst = higher ? values.min() : values.max(), best != worst else { return false }
        return v == best
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
                        Button { state.toggleFavoriteDepartement(d.codeInsee) } label: {
                            Image(systemName: "star.fill").foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Retirer des favoris")
                    }
                    .multilineTextAlignment(.center)
                    .frame(width: colW, alignment: .center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .overlay(Rectangle().fill(ClassicTheme.border).frame(width: 1), alignment: .leading)
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
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { _, c in
                            let best = isBest(c, in: row)
                            HStack(spacing: 8) {
                                Text(c.text)
                                    .font(CFont.sans(13, weight: best ? .semibold : .regular))
                                    .foregroundStyle(best ? ClassicTheme.ink : ClassicTheme.sub)
                                if best {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(theme.accent)
                                }
                            }
                            .frame(width: colW, alignment: .center)
                            .padding(.horizontal, 18).padding(.vertical, 13)
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

    // MARK: - Tableau transposé (départements en lignes, critères en colonnes)

    private var transposedTable: some View {
        let deps = departements
        let rows = sections.flatMap(\.rows)
        let nameColW: CGFloat = 200
        let critColW: CGFloat = 120
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("DÉPARTEMENT").font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.faint)
                    .frame(width: nameColW, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 14)
                ForEach(rows) { row in
                    Text(row.label).font(CFont.sans(12, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                        .multilineTextAlignment(.center)
                        .frame(width: critColW, alignment: .center)
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .overlay(Rectangle().fill(ClassicTheme.border).frame(width: 1), alignment: .leading)
                }
            }
            .background(ClassicTheme.sidebarBg)
            .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.border).frame(height: 1) }

            ForEach(Array(deps.enumerated()), id: \.element.codeInsee) { i, d in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.nom).font(CFont.sans(14, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                        Text("\(d.codeInsee) · \(d.nomRegion)").font(CFont.mono(10)).foregroundStyle(ClassicTheme.faint)
                    }
                    .frame(width: nameColW, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    ForEach(rows) { row in
                        let c = row.cells[i]
                        let best = isBest(c, in: row)
                        HStack(spacing: 6) {
                            Text(c.text)
                                .font(CFont.sans(13, weight: best ? .semibold : .regular))
                                .foregroundStyle(best ? ClassicTheme.ink : ClassicTheme.sub)
                            if best {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(theme.accent)
                            }
                        }
                        .frame(width: critColW, alignment: .center)
                        .padding(.horizontal, 12).padding(.vertical, 13)
                        .overlay(Rectangle().fill(ClassicTheme.dividerLight).frame(width: 1), alignment: .leading)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }
}
