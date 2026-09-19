import SwiftUI
import Charts

/// Fenêtre séparée détaillant la météo mensuelle d'un département (ouverte
/// par double-clic sur la section Météo de l'inspecteur) : graphiques
/// agrandis sur les 5 dernières années, cumuls/moyennes par année et
/// tableau année × mois.
public struct MeteoDetailView: View {
    /// Identifiant de la scène `WindowGroup(for: String.self)` déclarée par
    /// l'app — la valeur passée à `openWindow` est le code du département.
    public static let windowID = "meteo-detail"

    private enum Metric: String, CaseIterable, Identifiable {
        case temperature = "Moyennes"
        case maxTemperature = "Maximales"
        case precipitation = "Précipitations"
        var id: String { rawValue }
    }

    @StateObject private var theme = ClassicTheme()
    /// Instance propre à cette fenêtre, utilisée pour les favoris seulement
    /// (synchronisés avec la fenêtre principale via `UserDefaults`).
    @StateObject private var state = ClassicState()
    @State private var metric: Metric = .temperature
    /// Mois (1...12) sélectionné dans le tableau de détail.
    @State private var selectedMonth: Int?
    /// Date survolée dans chaque graphique (`chartXSelection`), pour l'infobulle.
    @State private var hoveredTemperatureDate: Date?
    @State private var hoveredPrecipitationDate: Date?
    let departementCode: String

    public init(departementCode: String) { self.departementCode = departementCode }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private var series: [MeteoMensuelle.Point] { MeteoMensuelle.series(forDepartementCode: departementCode) }
    private var name: String {
        FranceGeoData.departements.first { $0.codeInsee == departementCode }?.nom ?? departementCode
    }

    private func year(_ p: MeteoMensuelle.Point) -> Int { Self.calendar.component(.year, from: p.date) }
    private func month(_ p: MeteoMensuelle.Point) -> Int { Self.calendar.component(.month, from: p.date) }
    private var years: [Int] { Array(Set(series.map(year))).sorted() }

    private func value(_ p: MeteoMensuelle.Point) -> Double? {
        switch metric {
        case .temperature: p.temperature
        case .maxTemperature: p.maxTemperature
        case .precipitation: p.precipitation
        }
    }

    private var unit: String { metric == .precipitation ? "mm" : "°C" }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if series.isEmpty {
                    Text("Aucune donnée pour ce département.")
                        .font(CFont.sans(14)).foregroundStyle(ClassicTheme.faint)
                } else {
                    chartCard(title: "Températures moyennes et maximales mensuelles (°C)") {
                        let points = series.filter { $0.temperature != nil }
                        Chart {
                            yearBands
                            ForEach(points) { p in
                                LineMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", p.temperature ?? 0), series: .value("Série", "Moyenne"))
                                    .foregroundStyle(by: .value("Série", "Moyenne"))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", p.temperature ?? 0))
                                    .foregroundStyle(by: .value("Série", "Moyenne"))
                                    .symbolSize(p.partial ? 20 : 30)
                                if let tx = p.maxTemperature {
                                    LineMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", tx), series: .value("Série", "Maximale"))
                                        .foregroundStyle(by: .value("Série", "Maximale"))
                                        .interpolationMethod(.monotone)
                                    PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", tx))
                                        .foregroundStyle(by: .value("Série", "Maximale"))
                                        .symbolSize(p.partial ? 20 : 30)
                                }
                            }
                            ForEach(points.filter { selectedMonth == month($0) }) { p in
                                PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", p.temperature ?? 0))
                                    .foregroundStyle(ClassicTheme.ink).symbolSize(90)
                                if let tx = p.maxTemperature {
                                    PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", tx))
                                        .foregroundStyle(ClassicTheme.ink).symbolSize(90)
                                }
                            }
                            if let p = hoveredPoint(hoveredTemperatureDate, in: points) {
                                RuleMark(x: .value("Mois", p.date, unit: .month))
                                    .foregroundStyle(ClassicTheme.faint.opacity(0.5))
                                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                        tooltip(p, value: String(format: "Moy. %.1f °C", p.temperature ?? 0), secondary: p.maxTemperature.map { String(format: "Max. %.1f °C", $0) })
                                    }
                            }
                        }
                        .chartForegroundStyleScale(["Moyenne": theme.accent, "Maximale": Color(hex: 0xD98A1F)])
                        .chartXSelection(value: $hoveredTemperatureDate)
                        .chartGesture { proxy in monthTap(proxy, points: points) }
                        .chartYScale(domain: .automatic(includesZero: false))
                    }
                    chartCard(title: "Précipitations mensuelles (mm)") {
                        let points = series.filter { $0.precipitation != nil }
                        Chart {
                            yearBands
                            ForEach(points) { p in
                                BarMark(x: .value("Mois", p.date, unit: .month), y: .value("mm", p.precipitation ?? 0))
                                    .foregroundStyle((selectedMonth == month(p) ? ClassicTheme.ink : theme.accent).opacity(p.partial ? 0.4 : 0.8))
                            }
                            if let p = hoveredPoint(hoveredPrecipitationDate, in: points) {
                                RuleMark(x: .value("Mois", p.date, unit: .month))
                                    .foregroundStyle(ClassicTheme.faint.opacity(0.5))
                                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                        tooltip(p, value: String(format: "%.1f mm", p.precipitation ?? 0), secondary: nil)
                                    }
                            }
                        }
                        .chartXSelection(value: $hoveredPrecipitationDate)
                        .chartGesture { proxy in monthTap(proxy, points: points) }
                    }
                    yearlySummary
                    monthTable
                    Text("Moyenne des postes Météo-France du département. Le dernier mois est en cours (données partielles).")
                        .font(CFont.sans(11)).foregroundStyle(ClassicTheme.faint)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ClassicTheme.background)
        .frame(minWidth: 760, minHeight: 640)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name).font(CFont.sans(26, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
            Text(departementCode)
                .font(CFont.sans(16, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(ClassicTheme.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            Text("Météo · 5 dernières années").font(CFont.sans(14)).foregroundStyle(ClassicTheme.faint)
            Spacer(minLength: 8)
            let isFavorite = state.favoriteDepartementCodes.contains(departementCode)
            Button {
                state.toggleFavoriteDepartement(departementCode)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 22))
                    .foregroundStyle(isFavorite ? theme.accent : ClassicTheme.faint)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
        }
    }

    /// Domaine X : du premier mois de la série à la fin du dernier.
    private var xDomain: ClosedRange<Date> {
        let start = series.first?.date ?? Date()
        let end = series.last.flatMap { Self.calendar.date(byAdding: .month, value: 1, to: $0.date) } ?? start
        return start...end
    }

    /// Bandes grisées alternées par année civile (bornées au domaine X), avec
    /// l'année en haut à gauche de chaque bande.
    @ChartContentBuilder
    private var yearBands: some ChartContent {
        let domain = xDomain
        ForEach(years, id: \.self) { y in
            let yearStart = Self.calendar.date(from: DateComponents(year: y, month: 1, day: 1))!
            let nextYear = Self.calendar.date(from: DateComponents(year: y + 1, month: 1, day: 1))!
            RectangleMark(xStart: .value("Début", max(yearStart, domain.lowerBound), unit: .month),
                          xEnd: .value("Fin", min(nextYear, domain.upperBound), unit: .month))
                .foregroundStyle((y - years[0]) % 2 == 0 ? ClassicTheme.track.opacity(0.45) : .clear)
                .annotation(position: .overlay, alignment: .topLeading, spacing: 0) {
                    Text(String(y))
                        .font(CFont.mono(11, weight: .bold)).foregroundStyle(ClassicTheme.ink)
                        .padding(.leading, 6).padding(.top, 3)
                }
        }
    }

    /// Clic sur un graphique : sélectionne le mois cliqué (même sélection que
    /// le tableau de détail) ; les points/barres du même mois de chaque année
    /// changent de couleur. Recliquer sur le même mois désélectionne.
    private func monthTap(_ proxy: ChartProxy, points: [MeteoMensuelle.Point]) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let date = proxy.value(atX: value.location.x, as: Date.self),
                  let p = hoveredPoint(date, in: points) else { return }
            let m = month(p)
            selectedMonth = selectedMonth == m ? nil : m
        }
    }

    /// Point du mois contenant la date survolée (les marques sont placées par
    /// mois, `unit: .month`).
    private func hoveredPoint(_ date: Date?, in points: [MeteoMensuelle.Point]) -> MeteoMensuelle.Point? {
        guard let date else { return nil }
        return points.last { $0.date <= date }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private func tooltip(_ p: MeteoMensuelle.Point, value: String, secondary: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.monthFormatter.string(from: p.date).capitalized)
                .font(CFont.sans(11)).foregroundStyle(ClassicTheme.faint)
            Text(value).font(CFont.sans(13, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
            if let secondary { Text(secondary).font(CFont.sans(13, weight: .semibold)).foregroundStyle(ClassicTheme.ink) }
            if p.partial { Text("mois en cours").font(CFont.sans(10)).foregroundStyle(ClassicTheme.faint2) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    private func chartCard<C: View>(title: String, @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(CFont.sans(13, weight: .medium)).foregroundStyle(ClassicTheme.sub)
            chart()
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    // Repères mensuels discrets, trimestres nommés ; les années
                    // sont indiquées dans les bandes (voir `yearBands`).
                    AxisMarks(values: .stride(by: .month)) { value in
                        let m = value.as(Date.self).map { Self.calendar.component(.month, from: $0) } ?? 0
                        AxisTick(length: 3).foregroundStyle(ClassicTheme.faint2)
                        if m == 1 || m == 4 || m == 7 || m == 10 {
                            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                                .font(CFont.mono(9)).foregroundStyle(ClassicTheme.faint)
                        }
                    }
                }
                .frame(height: 230)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }

    /// Par année civile : température moyenne et cumul de pluie sur les mois
    /// disponibles (première et dernière années partielles).
    private var yearlySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Par année").font(CFont.sans(13, weight: .medium)).foregroundStyle(ClassicTheme.sub)
            HStack(spacing: 12) {
                ForEach(years, id: \.self) { y in
                    let pts = series.filter { year($0) == y }
                    let temps = pts.compactMap(\.temperature)
                    let rain = pts.compactMap(\.precipitation)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(y)).font(CFont.mono(11, weight: .semibold)).foregroundStyle(ClassicTheme.faint)
                        Text(temps.isEmpty ? "–" : String(format: "%.1f °C", temps.reduce(0, +) / Double(temps.count)))
                            .font(CFont.sans(16, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                        Text(rain.isEmpty ? "–" : String(format: "%.0f mm", rain.reduce(0, +)))
                            .font(CFont.sans(13)).foregroundStyle(ClassicTheme.sub)
                        Text("\(pts.count) mois").font(CFont.sans(11)).foregroundStyle(ClassicTheme.faint2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClassicTheme.border, lineWidth: 1))
                }
            }
        }
    }

    /// Tableau mois (lignes) × années (colonnes), commutable entre
    /// températures et précipitations.
    private var monthTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Détail par mois").font(CFont.sans(13, weight: .medium)).foregroundStyle(ClassicTheme.sub)
                Spacer()
                Picker("", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("").frame(width: 110, alignment: .leading)
                    ForEach(years, id: \.self) {
                        Text(String($0)).font(CFont.mono(11, weight: .semibold)).foregroundStyle(ClassicTheme.faint)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
                Divider().padding(.bottom, 2)
                ForEach(1...12, id: \.self) { m in
                    let isSelected = selectedMonth == m
                    HStack(spacing: 0) {
                        Text(Self.monthName(m)).font(CFont.sans(13, weight: isSelected ? .semibold : .regular)).foregroundStyle(ClassicTheme.body)
                            .frame(width: 110, alignment: .leading)
                        ForEach(years, id: \.self) { y in
                            let p = series.first { year($0) == y && month($0) == m }
                            Text(p.flatMap(value).map { String(format: metric == .precipitation ? "%.0f" : "%.1f", $0) } ?? "–")
                                .font(CFont.mono(12))
                                .foregroundStyle(p?.partial == true ? ClassicTheme.faint : ClassicTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(isSelected ? theme.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    // Un clic sélectionne la ligne entière ; recliquer la désélectionne.
                    .onTapGesture { selectedMonth = isSelected ? nil : m }
                }
            }
            Text("Valeurs en \(unit).").font(CFont.sans(11)).foregroundStyle(ClassicTheme.faint2)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }

    private static func monthName(_ m: Int) -> String {
        let names = ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]
        return names[m - 1]
    }
}
