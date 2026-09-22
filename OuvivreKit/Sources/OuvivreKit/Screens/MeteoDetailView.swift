import SwiftUI
import Charts
import MapKit

/// Fenêtre séparée détaillant la météo mensuelle d'un département (ouverte
/// par double-clic sur la section Météo de l'inspecteur) : graphiques
/// agrandis sur les 5 dernières années, cumuls/moyennes par année et
/// tableau année × mois.
public struct MeteoDetailView: View {
    /// Identifiant de la scène `WindowGroup(for: String.self)` déclarée par
    /// l'app — la valeur passée à `openWindow` est le code du département.
    public static let windowID = "meteo-detail"

    /// Température ressentie masquée pour le moment : les données (`tr`) restent
    /// dans le JSON, repasser à `true` pour réafficher courbe, infobulle et bouton.
    private static let showFeltTemperature = false

    /// Synthèse rédigée masquée pour le moment : repasser à `true` pour la réafficher.
    private static let showSynthesis = false

    private enum RainGrouping: String, CaseIterable, Identifiable {
        case month = "Mois", quarter = "Trimestres"
        var id: String { rawValue }
    }

    private enum Metric: String, CaseIterable, Identifiable {
        case temperature = "Moyennes"
        case maxTemperature = "Maximales"
        case record = "Records"
        case felt = "Ressenties"
        case precipitation = "Précipitations"
        var id: String { rawValue }
        static var available: [Metric] { allCases.filter { $0 != .felt || MeteoDetailView.showFeltTemperature } }
        var icon: String {
            switch self {
            case .temperature: "thermometer.medium"
            case .maxTemperature: "thermometer.high"
            case .record: "thermometer.sun"
            case .felt: "thermometer.variable.and.figure"
            case .precipitation: "cloud.rain"
            }
        }
    }

    @StateObject private var theme = ClassicTheme()
    /// Instance propre à cette fenêtre, utilisée pour les favoris seulement
    /// (synchronisés avec la fenêtre principale via `UserDefaults`).
    @StateObject private var state = ClassicState()
    @State private var mapFocusTick = 0
    @State private var metric: Metric = .temperature
    /// Mois (1...12) sélectionné dans le tableau de détail.
    /// À l'ouverture, le mois courant est sélectionné par défaut.
    @State private var selectedMonth: Int? = MeteoDetailView.calendar.component(.month, from: Date())
    /// Année de la valeur cliquée dans un graphique : met en évidence son bloc
    /// dans « Moyennes annuelles ».
    @State private var selectedYear: Int?
    @FocusState private var isFocused: Bool
    /// Date survolée dans chaque graphique (`chartXSelection`), pour l'infobulle.
    @State private var hoveredTemperatureDate: Date?
    @State private var hoveredPrecipitationDate: Date?
    /// Regroupement des barres de précipitations : par mois ou par trimestre.
    @State private var rainGrouping: RainGrouping = .month
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
        case .record: p.absoluteMax
        case .felt: p.feltTemperature
        case .precipitation: p.precipitation
        }
    }

    private var unit: String { metric == .precipitation ? "mm" : "°C" }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                DepartementMapCard(name: name, accent: theme.accent, focusCoordinate: FranceGeoData.chefsLieuxCoordinates[departementCode], focusTick: mapFocusTick, roundedFont: true)
                if Self.showSynthesis { synthesisView }
                if series.isEmpty {
                    Text("Aucune donnée pour ce département.")
                        .font(CFont.rounded(13)).foregroundStyle(ClassicTheme.faint)
                } else {
                    chartCard(title: Self.showFeltTemperature ? "Températures moyennes, ressenties, maximales et records mensuels (°C)" : "Températures moyennes, maximales et records mensuels (°C)", yTicks: Array(temperatureAxis.ticks)) {
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
                                if Self.showFeltTemperature, let tr = p.feltTemperature {
                                    LineMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", tr), series: .value("Série", "Ressentie"))
                                        .foregroundStyle(by: .value("Série", "Ressentie"))
                                        .interpolationMethod(.monotone)
                                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                }
                                if let xa = p.absoluteMax {
                                    LineMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", xa), series: .value("Série", "Record absolu"))
                                        .foregroundStyle(by: .value("Série", "Record absolu"))
                                        .interpolationMethod(.monotone)
                                    PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", xa))
                                        .foregroundStyle(by: .value("Série", "Record absolu"))
                                        .symbolSize(p.partial ? 20 : 30)
                                }
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
                                // Infobulle permanente sur le point le plus haut du mois
                                // sélectionné, pour chaque année.
                                PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", p.maxTemperature ?? p.temperature ?? 0))
                                    .foregroundStyle(ClassicTheme.ink).symbolSize(p.maxTemperature == nil ? 0 : 90)
                                recordHighlight(p)
                                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                        tooltip(p, value: "Moy. \(frDecimal(p.temperature ?? 0)) °C", secondary: temperatureLines(p))
                                    }
                            }
                            if let p = hoveredPoint(hoveredTemperatureDate, in: points), selectedMonth != month(p) {
                                highlightMarks(p)
                                RuleMark(x: .value("Mois", p.date, unit: .month))
                                    .foregroundStyle(ClassicTheme.faint.opacity(0.5))
                                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                        tooltip(p, value: "Moy. \(frDecimal(p.temperature ?? 0)) °C", secondary: temperatureLines(p))
                                    }
                            }
                        }
                        .chartForegroundStyleScale(Self.showFeltTemperature
                            ? ["Moyenne": theme.accent, "Ressentie": Color(hex: 0x2F7F8F), "Maximale": Color(hex: 0xD98A1F), "Record absolu": Color(hex: 0x8E3B6E)]
                            : ["Moyenne": theme.accent, "Maximale": Color(hex: 0xD98A1F), "Record absolu": Color(hex: 0x8E3B6E)])
                        .chartXSelection(value: $hoveredTemperatureDate)
                        .chartGesture { proxy in monthTap(proxy, points: points) }
                        .chartYScale(domain: temperatureAxis.domain)
                    }
                    chartCard(title: rainGrouping == .month ? "Précipitations mensuelles (mm)" : "Précipitations trimestrielles (moyenne mensuelle du trimestre, mm)", trailing: { groupingButtons }) {
                        let points = series.filter { $0.precipitation != nil }
                        let quarters = rainQuarters
                        Chart {
                            yearBands
                            if rainGrouping == .month {
                                ForEach(points) { p in
                                    BarMark(x: .value("Mois", p.date, unit: .month), y: .value("mm", p.precipitation ?? 0))
                                        .foregroundStyle((selectedMonth == month(p) ? ClassicTheme.ink : theme.accent).opacity(p.partial ? 0.4 : 0.8))
                                }
                                ForEach(points.filter { selectedMonth == month($0) }) { p in
                                    PointMark(x: .value("Mois", p.date, unit: .month), y: .value("mm", p.precipitation ?? 0))
                                        .opacity(0)
                                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                            tooltip(p, value: "\(frDecimal(p.precipitation ?? 0)) mm", secondary: nil)
                                        }
                                }
                                if let p = hoveredPoint(hoveredPrecipitationDate, in: points), selectedMonth != month(p) {
                                    RuleMark(x: .value("Mois", p.date, unit: .month))
                                        .foregroundStyle(ClassicTheme.faint.opacity(0.5))
                                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                            tooltip(p, value: "\(frDecimal(p.precipitation ?? 0)) mm", secondary: nil)
                                        }
                                }
                            } else {
                                // Une barre par trimestre civil, de la largeur du
                                // trimestre (légèrement réduite pour séparer les barres).
                                ForEach(quarters) { q in
                                    quarterBar(q)
                                }
                                ForEach(quarters.filter(selectedQuarterContains)) { q in
                                    PointMark(x: .value("Trimestre", q.middle), y: .value("mm", q.mean))
                                        .opacity(0)
                                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                            quarterTooltip(q)
                                        }
                                }
                                if let date = hoveredPrecipitationDate, let q = quarters.last(where: { $0.start <= date }),
                                   !selectedQuarterContains(q) {
                                    RuleMark(x: .value("Trimestre", q.middle))
                                        .foregroundStyle(ClassicTheme.faint.opacity(0.5))
                                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                            quarterTooltip(q)
                                        }
                                }
                            }
                        }
                        .chartXSelection(value: $hoveredPrecipitationDate)
                        .chartGesture { proxy in monthTap(proxy, points: points) }
                        // Même échelle verticale (0 → plus fort cumul mensuel) en
                        // vue Mois et Trimestres, pour comparer les deux.
                        .chartYScale(domain: 0...rainScaleMax)
                    }
                    yearlySummary
                    monthTable
                    Text("Moyenne des postes Météo-France du département. Le dernier mois est en cours (données partielles).")
                        .font(CFont.rounded(11)).foregroundStyle(ClassicTheme.faint)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .departementDetailWindow()
        // Flèches gauche/droite : mois précédent/suivant de la sélection
        // (graphiques et tableau), sans effet tant qu'aucun mois n'est
        // sélectionné.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: selectedMonth) { _, new in
            if new != nil { isFocused = true } else { selectedYear = nil }
        }
        .onKeyPress(.leftArrow) { moveSelection(by: -1) }
        .onKeyPress(.rightArrow) { moveSelection(by: 1) }
    }

    // MARK: Synthèse

    private static func fmt(_ v: Double, _ digits: Int = 1) -> String {
        frDecimal(v, digits: digits)
    }

    private static func signed(_ v: Double, _ digits: Int = 1) -> String {
        (v >= 0 ? "+" : "−") + fmt(abs(v), digits)
    }

    private func label(_ p: MeteoMensuelle.Point) -> String { "\(Self.monthName(month(p))) \(year(p))" }

    /// Synthèse rédigée à partir des données : écarts entre années complètes,
    /// année en cours comparée aux mêmes mois des années précédentes, et mois
    /// atypiques (écart à la moyenne du même mois des autres années).
    private var synthesis: [(title: String, text: String)] {
        let pts = series
        guard let currentYear = years.last, years.count >= 2 else { return [] }
        let byYear = Dictionary(grouping: pts, by: year)
        let complete = years.filter { y in
            let list = byYear[y] ?? []
            return list.count == 12 && list.allSatisfy { $0.temperature != nil && $0.precipitation != nil && !$0.partial }
        }
        func annualTemp(_ y: Int) -> Double { let t = (byYear[y] ?? []).compactMap(\.temperature); return t.reduce(0, +) / Double(t.count) }
        func annualRain(_ y: Int) -> Double { (byYear[y] ?? []).compactMap(\.precipitation).reduce(0, +) }

        // Année en cours, mois entiers seulement, vs mêmes mois des autres années.
        let currentPts = (byYear[currentYear] ?? []).filter { !$0.partial }
        func baseline(_ m: Int, _ v: (MeteoMensuelle.Point) -> Double?, excluding y: Int) -> Double? {
            let vals = pts.filter { month($0) == m && year($0) != y }.compactMap(v)
            return vals.count >= 2 ? vals.reduce(0, +) / Double(vals.count) : nil
        }
        let ytdMonths = currentPts.map(month)
        let lastMonthName = ytdMonths.max().map { Self.monthName($0).lowercased() }

        var tempText: [String] = []
        if complete.count >= 2, let first = complete.first, let last = complete.last,
           let hot = complete.max(by: { annualTemp($0) < annualTemp($1) }),
           let cold = complete.min(by: { annualTemp($0) < annualTemp($1) }) {
            var sentence = "Sur les années complètes \(first)–\(last), la température annuelle moyenne va de \(Self.fmt(annualTemp(cold))) °C (\(cold), la plus fraîche) à \(Self.fmt(annualTemp(hot))) °C (\(hot), la plus chaude)"
            let delta = annualTemp(last) - annualTemp(first)
            if abs(delta) >= 0.1 { sentence += ", soit \(Self.signed(delta)) °C entre \(first) et \(last)" }
            tempText.append(sentence + ".")
        }
        let tempPairs = currentPts.compactMap { p -> (Double, Double)? in
            guard let t = p.temperature, let b = baseline(month(p), { $0.temperature }, excluding: currentYear) else { return nil }
            return (t, b)
        }
        if !tempPairs.isEmpty, let lastMonthName {
            let cur = tempPairs.map(\.0).reduce(0, +) / Double(tempPairs.count)
            let base = tempPairs.map(\.1).reduce(0, +) / Double(tempPairs.count)
            let d = cur - base
            tempText.append(abs(d) < 0.2
                ? "De janvier à \(lastMonthName) \(currentYear), la moyenne (\(Self.fmt(cur)) °C) est proche de celle des mêmes mois des années précédentes."
                : "De janvier à \(lastMonthName) \(currentYear), la moyenne (\(Self.fmt(cur)) °C) est \(Self.fmt(abs(d))) °C \(d > 0 ? "au-dessus" : "en dessous") de celle des mêmes mois des années précédentes.")
        }

        var rainText: [String] = []
        if complete.count >= 2,
           let wet = complete.max(by: { annualRain($0) < annualRain($1) }),
           let dry = complete.min(by: { annualRain($0) < annualRain($1) }) {
            var sentence = "Les cumuls annuels vont de \(Self.fmt(annualRain(dry), 0)) mm (\(dry), la plus sèche) à \(Self.fmt(annualRain(wet), 0)) mm (\(wet), la plus arrosée)"
            if annualRain(dry) > 0 {
                let gap = (annualRain(wet) / annualRain(dry) - 1) * 100
                if gap >= 5 { sentence += ", soit \(Self.fmt(gap, 0)) % d'écart" }
            }
            rainText.append(sentence + ".")
        }
        let rainPairs = currentPts.compactMap { p -> (Double, Double)? in
            guard let r = p.precipitation, let b = baseline(month(p), { $0.precipitation }, excluding: currentYear) else { return nil }
            return (r, b)
        }
        if !rainPairs.isEmpty, let lastMonthName {
            let cur = rainPairs.map(\.0).reduce(0, +)
            let base = rainPairs.map(\.1).reduce(0, +)
            if base > 0 {
                let d = (cur / base - 1) * 100
                rainText.append(abs(d) < 5
                    ? "De janvier à \(lastMonthName) \(currentYear), \(Self.fmt(cur, 0)) mm sont tombés, un niveau proche de la moyenne des mêmes mois."
                    : "De janvier à \(lastMonthName) \(currentYear), \(Self.fmt(cur, 0)) mm sont tombés, soit \(Self.fmt(abs(d), 0)) % \(d > 0 ? "de plus" : "de moins") que la moyenne des mêmes mois des années précédentes.")
            }
        }

        // Mois atypiques.
        var notable: [String] = []
        let complet = pts.filter { !$0.partial }
        let tempAnoms = complet.compactMap { p -> (MeteoMensuelle.Point, Double)? in
            guard let t = p.temperature, let b = baseline(month(p), { $0.temperature }, excluding: year(p)) else { return nil }
            return (p, t - b)
        }
        if let top = tempAnoms.max(by: { abs($0.1) < abs($1.1) }), abs(top.1) >= 2 {
            notable.append("\(label(top.0)) est le mois le plus atypique en température : \(Self.fmt(top.0.temperature ?? 0)) °C, soit \(Self.fmt(abs(top.1))) °C \(top.1 > 0 ? "au-dessus" : "en dessous") de la moyenne des autres \(Self.monthName(month(top.0)).lowercased()).")
        }
        let rainAnoms = complet.compactMap { p -> (MeteoMensuelle.Point, Double, Double)? in
            guard let r = p.precipitation, let b = baseline(month(p), { $0.precipitation }, excluding: year(p)), b >= 15 else { return nil }
            return (p, r / b, b)
        }
        if let wet = rainAnoms.max(by: { $0.1 < $1.1 }), wet.1 >= 2 {
            notable.append("\(label(wet.0)) est exceptionnellement arrosé : \(Self.fmt(wet.0.precipitation ?? 0, 0)) mm, soit \(Self.fmt(wet.1)) fois la moyenne des autres \(Self.monthName(month(wet.0)).lowercased()) (\(Self.fmt(wet.2, 0)) mm).")
        }
        if let dry = rainAnoms.min(by: { $0.1 < $1.1 }), dry.1 <= 0.25 {
            notable.append("\(label(dry.0)) est quasi sec : \(Self.fmt(dry.0.precipitation ?? 0, 0)) mm contre \(Self.fmt(dry.2, 0)) mm en moyenne pour les autres \(Self.monthName(month(dry.0)).lowercased()).")
        }
        if let hottest = complet.compactMap({ p in p.temperature.map { (p, $0) } }).max(by: { $0.1 < $1.1 }),
           let coldest = complet.compactMap({ p in p.temperature.map { (p, $0) } }).min(by: { $0.1 < $1.1 }) {
            notable.append("Mois le plus chaud : \(label(hottest.0)) (\(Self.fmt(hottest.1)) °C) ; le plus froid : \(label(coldest.0)) (\(Self.fmt(coldest.1)) °C).")
        }

        var result: [(String, String)] = []
        if !tempText.isEmpty { result.append(("Températures.", tempText.joined(separator: " "))) }
        if !rainText.isEmpty { result.append(("Précipitations.", rainText.joined(separator: " "))) }
        if !notable.isEmpty { result.append(("À noter.", notable.joined(separator: " "))) }
        return result
    }

    @ViewBuilder
    private var synthesisView: some View {
        let paragraphs = synthesis
        if !paragraphs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(paragraphs, id: \.title) { paragraph in
                    Text(paragraph.title + " ").font(CFont.sans(13, weight: .semibold)).foregroundColor(ClassicTheme.ink)
                        + Text(paragraph.text).font(CFont.sans(13)).foregroundColor(ClassicTheme.body)
                }
            }
            .lineSpacing(2)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var header: some View {
        DepartementDetailHeader(departementCode: departementCode, name: name, accent: theme.accent, state: state) { mapFocusTick += 1 }
    }

    /// Domaine X : du premier mois de la série à la fin du dernier.
    private var xDomain: ClosedRange<Date> {
        let start = series.first?.date ?? Date()
        let end = series.last.flatMap { Self.calendar.date(byAdding: .month, value: 1, to: $0.date) } ?? start
        return start...end
    }

    /// Point du record absolu mis en évidence avec la moyenne et la maximale.
    @ChartContentBuilder
    private func recordHighlight(_ p: MeteoMensuelle.Point) -> some ChartContent {
        if let xa = p.absoluteMax {
            PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", xa))
                .foregroundStyle(ClassicTheme.ink).symbol(.diamond).symbolSize(90)
        }
    }

    /// Au survol d'un mois : moyenne, maximale et record mis en évidence ensemble.
    @ChartContentBuilder
    private func highlightMarks(_ p: MeteoMensuelle.Point) -> some ChartContent {
        PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", p.temperature ?? 0))
            .foregroundStyle(ClassicTheme.ink).symbolSize(90)
        if let tx = p.maxTemperature {
            PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", tx))
                .foregroundStyle(ClassicTheme.ink).symbolSize(90)
        }
        recordHighlight(p)
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
                        .font(CFont.rounded(11, weight: .bold)).foregroundStyle(ClassicTheme.ink)
                        .padding(.leading, 6).padding(.top, 3)
                }
        }
    }

    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard let m = selectedMonth else { return .ignored }
        selectedMonth = max(1, min(12, m + delta))
        return .handled
    }

    /// Clic sur un graphique : sélectionne le mois cliqué (même sélection que
    /// le tableau de détail) ; les points/barres du même mois de chaque année
    /// changent de couleur. Recliquer sur le même mois désélectionne.
    private func monthTap(_ proxy: ChartProxy, points: [MeteoMensuelle.Point]) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let date = proxy.value(atX: value.location.x, as: Date.self),
                  let p = hoveredPoint(date, in: points) else { return }
            let m = month(p), y = year(p)
            if selectedMonth == m && selectedYear == y {
                selectedMonth = nil
                selectedYear = nil
            } else {
                selectedMonth = m
                selectedYear = y
            }
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

    /// Lignes complémentaires de l'infobulle de température : ressentie (si
    /// affichée), maximale moyenne et record absolu (sans poste ni date).
    private func temperatureLines(_ p: MeteoMensuelle.Point) -> String {
        var lines: [String] = []
        if Self.showFeltTemperature, let tr = p.feltTemperature { lines.append("Ress. \(frDecimal(tr)) °C") }
        if let tx = p.maxTemperature { lines.append("Max. \(frDecimal(tx)) °C") }
        if let xa = p.absoluteMax {
            let line = "Record \(frDecimal(xa)) °C"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private func tooltip(_ p: MeteoMensuelle.Point, value: String, secondary: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Self.monthFormatter.string(from: p.date).capitalized)
                .font(CFont.rounded(12, weight: .medium)).foregroundStyle(ClassicTheme.faint)
            Text(value).font(CFont.rounded(12, weight: .medium)).foregroundStyle(ClassicTheme.ink)
            if let secondary, !secondary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(secondary.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                        // Le nombre du record de température est en rouge.
                        if line.hasPrefix("Record ") {
                            Text("Record ").font(CFont.rounded(12, weight: .medium)).foregroundColor(ClassicTheme.ink)
                                + Text(line.dropFirst("Record ".count)).font(CFont.rounded(12, weight: .medium)).foregroundColor(.red)
                        } else {
                            Text(line).font(CFont.rounded(12, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                        }
                    }
                }
            }
            if p.partial { Text("mois en cours").font(CFont.rounded(12, weight: .medium)).foregroundStyle(ClassicTheme.faint2) }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    // MARK: Précipitations par trimestre

    private struct RainQuarter: Identifiable {
        let start: Date
        let end: Date
        let year: Int
        let quarter: Int
        /// Moyenne des cumuls mensuels du trimestre (mm/mois), sur les mois
        /// disponibles.
        let mean: Double
        let monthCount: Int
        let months: ClosedRange<Int>
        /// Le trimestre contient le mois en cours (données partielles).
        let partial: Bool
        var id: Date { start }
        var middle: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    }

    private var rainQuarters: [RainQuarter] {
        let groups = Dictionary(grouping: series.filter { $0.precipitation != nil }) { year($0) * 4 + (month($0) - 1) / 3 }
        return groups.compactMap { key, pts -> RainQuarter? in
            let (y, q) = (key / 4, key % 4)
            let firstMonth = q * 3 + 1
            guard let start = Self.calendar.date(from: DateComponents(year: y, month: firstMonth, day: 1)),
                  let end = Self.calendar.date(byAdding: .month, value: 3, to: start) else { return nil }
            let values = pts.compactMap(\.precipitation)
            return RainQuarter(start: start, end: end, year: y, quarter: q + 1,
                               mean: values.reduce(0, +) / Double(values.count), monthCount: values.count,
                               months: firstMonth...(firstMonth + 2), partial: pts.contains { $0.partial })
        }
        .sorted { $0.start < $1.start }
    }

    /// Axe des températures : bornes arrondies au multiple de 5 °C, graduations
    /// sans la valeur maximale (la borne haute n'est pas étiquetée).
    private var temperatureAxis: (domain: ClosedRange<Double>, ticks: [Double]) {
        let values = series.flatMap { [$0.temperature, $0.maxTemperature, $0.absoluteMax] }.compactMap { $0 }
        guard let lo = values.min(), let hi = values.max() else { return (0...10, [0, 5]) }
        let low = (lo / 5).rounded(.down) * 5
        let high = max((hi / 5).rounded(.up) * 5, low + 5)
        return (low...high, Array(stride(from: low, to: high, by: 5)))
    }

    /// Borne haute de l'axe des précipitations : le plus fort cumul mensuel,
    /// arrondi à la dizaine supérieure.
    private var rainScaleMax: Double {
        let peak = series.compactMap(\.precipitation).max() ?? 10
        return max(10, (peak / 10).rounded(.up) * 10)
    }

    /// Barre d'un trimestre : de zéro à la moyenne mensuelle, sur la largeur du
    /// trimestre (réduite de 4 jours pour séparer les barres).
    @ChartContentBuilder
    private func quarterBar(_ q: RainQuarter) -> some ChartContent {
        let color: Color = selectedQuarterContains(q) ? ClassicTheme.ink : theme.accent
        let barEnd = q.end.addingTimeInterval(-4 * 86_400)
        RectangleMark(xStart: .value("Début", q.start), xEnd: .value("Fin", barEnd),
                      yStart: .value("Base", 0.0), yEnd: .value("mm", q.mean))
            .foregroundStyle(color.opacity(q.partial ? 0.4 : 0.8))
    }

    private func selectedQuarterContains(_ q: RainQuarter) -> Bool {
        selectedMonth.map { q.months.contains($0) } ?? false
    }

    private func quarterTooltip(_ q: RainQuarter) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: "\(Self.monthName(q.months.lowerBound).prefix(4)).–\(Self.monthName(q.months.upperBound).prefix(4)).")
                .font(CFont.rounded(12, weight: .medium)).foregroundStyle(ClassicTheme.faint)
            Text(verbatim: "\(frDecimal(q.mean)) mm/mois").font(CFont.rounded(12, weight: .medium)).foregroundStyle(ClassicTheme.ink)
            if q.partial {
                Text("trimestre en cours").font(CFont.rounded(12, weight: .medium)).foregroundStyle(ClassicTheme.faint2)
            } else if q.monthCount < 3 {
                Text("\(q.monthCount) mois disponibles").font(CFont.rounded(12, weight: .medium)).foregroundStyle(ClassicTheme.faint2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ClassicTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    /// Boutons Mois / Trimestres, dans le style des boutons Explorer / Satellite
    /// de la carte (capsule), remplie de la couleur d'accent quand actif.
    private var groupingButtons: some View {
        HStack(spacing: 8) {
            ForEach(RainGrouping.allCases) { g in
                Button { rainGrouping = g } label: {
                    Text(g.rawValue)
                        .font(CFont.rounded(12, weight: .medium))
                        .foregroundStyle(rainGrouping == g ? .white : ClassicTheme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(rainGrouping == g ? theme.accent : .clear)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(rainGrouping == g ? theme.accent : ClassicTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(g == .month ? "Afficher les précipitations par mois" : "Afficher la moyenne mensuelle par trimestre")
            }
        }
    }

    private func chartCard<C: View>(title: String, yTicks: [Double]? = nil, @ViewBuilder chart: () -> C) -> some View {
        chartCard(title: title, yTicks: yTicks, trailing: { EmptyView() }, chart: chart)
    }

    private func chartCard<C: View, T: View>(title: String, yTicks: [Double]? = nil, @ViewBuilder trailing: () -> T, @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(title).font(CFont.rounded(13, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                Spacer(minLength: 8)
                trailing()
            }
            chart()
                .font(CFont.rounded(11))
                .chartYAxis {
                    if let yTicks {
                        AxisMarks(values: yTicks) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel().font(CFont.rounded(11)).foregroundStyle(ClassicTheme.faint)
                        }
                    } else {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel().font(CFont.rounded(11)).foregroundStyle(ClassicTheme.faint)
                        }
                    }
                }
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    // Repères mensuels discrets, trimestres nommés ; les années
                    // sont indiquées dans les bandes (voir `yearBands`).
                    AxisMarks(values: .stride(by: .month)) { value in
                        let m = value.as(Date.self).map { Self.calendar.component(.month, from: $0) } ?? 0
                        AxisTick(length: 3).foregroundStyle(ClassicTheme.faint2)
                        if m == 1 || m == 4 || m == 7 || m == 10 {
                            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                                .font(CFont.rounded(9)).foregroundStyle(ClassicTheme.faint)
                        }
                    }
                }
                .frame(height: 325)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }

    /// Par année civile : température moyenne et cumul de pluie sur les mois
    /// disponibles (première et dernière années partielles).
    private var yearlySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Moyennes annuelles").font(CFont.rounded(13, weight: .medium)).foregroundStyle(ClassicTheme.ink)
            HStack(spacing: 12) {
                ForEach(years, id: \.self) { y in
                    let pts = series.filter { year($0) == y }
                    let temps = pts.compactMap(\.temperature)
                    let rain = pts.compactMap(\.precipitation)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(y)).font(CFont.rounded(11, weight: .bold)).foregroundStyle(ClassicTheme.ink)
                            .padding(.bottom, 3)
                        HStack(spacing: 5) {
                            Image(systemName: "thermometer.medium").font(.system(size: 13)).foregroundStyle(theme.accent)
                            Text(temps.isEmpty ? "–" : "\(frDecimal(temps.reduce(0, +) / Double(temps.count))) °C")
                                .font(CFont.sans(16, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "cloud.rain").font(.system(size: 12)).foregroundStyle(theme.accent)
                            Text(rain.isEmpty ? "–" : String(format: "%.0f mm", rain.reduce(0, +)))
                                .font(CFont.sans(13)).foregroundStyle(ClassicTheme.sub)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedYear == y ? theme.accent.opacity(0.12) : Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedYear == y ? theme.accent : ClassicTheme.border, lineWidth: selectedYear == y ? 1.5 : 1))
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }

    /// Tableau mois (lignes) × années (colonnes), commutable entre
    /// températures et précipitations.
    private var monthTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Détail par mois des températures (°C) et précipitations (mm)").font(CFont.rounded(13, weight: .medium)).foregroundStyle(ClassicTheme.ink)
            // Sur sa propre ligne, à largeur naturelle : trois boutons avec
            // icône ne tiennent pas dans un sélecteur segmenté à côté du titre.
            HStack(spacing: 8) {
                ForEach(Metric.available) { m in
                    let isOn = metric == m
                    Button { metric = m } label: {
                        Label(m.rawValue, systemImage: m.icon)
                            .font(CFont.sans(12, weight: .medium))
                            .foregroundStyle(isOn ? Color.white : ClassicTheme.body)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(isOn ? theme.accent : ClassicTheme.track.opacity(0.6), in: Capsule())
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("").frame(width: 110, alignment: .leading)
                    ForEach(years, id: \.self) {
                        Text(String($0)).font(CFont.rounded(11, weight: .bold)).foregroundStyle(ClassicTheme.ink)
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
                            Text(p.flatMap(value).map { metric == .precipitation ? String(format: "%.0f", $0) : frDecimal($0) } ?? "–")
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
