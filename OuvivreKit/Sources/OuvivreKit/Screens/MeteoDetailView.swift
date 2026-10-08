import SwiftUI
import Charts

/// Fenêtre séparée détaillant la météo mensuelle d'un département (ouverte
/// par double-clic sur la section Météo de l'inspecteur) : graphiques
/// agrandis sur les 5 dernières années, cumuls/moyennes par année et
/// tableau année × mois.
public struct MeteoDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }
    /// Identifiant de la scène `WindowGroup(for: String.self)` déclarée par
    /// l'app — la valeur passée à `openWindow` est le code du département.
    public static let windowID = "meteo-detail"

    private enum RainGrouping: String, CaseIterable, Identifiable {
        case month = "Mois", quarter = "Trimestres"
        var id: String { rawValue }
    }

    private enum Metric: String, CaseIterable, Identifiable {
        case temperature = "Moyennes"
        case maxTemperature = "Maximales"
        case record = "Records"
        case precipitation = "Précipitations"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .temperature: "thermometer.medium"
            case .maxTemperature: "thermometer.high"
            case .record: "sun.max.fill"
            case .precipitation: "cloud.rain"
            }
        }
    }

    /// Instance propre à cette fenêtre, utilisée pour les favoris seulement
    /// (synchronisés avec la fenêtre principale via `UserDefaults`).
    @StateObject private var state = ClassicState()
    @State private var metric: Metric = .temperature
    /// Mois (1...12) sélectionné dans le tableau de détail.
    /// À l'ouverture, le mois courant est sélectionné par défaut.
    @State private var selectedMonth: Int? = MeteoMensuelle.calendar.component(.month, from: Date())
    /// Année de la valeur cliquée dans un graphique : met en évidence son bloc
    /// dans « Moyennes annuelles ».
    @State private var selectedYear: Int?
    @FocusState private var isFocused: Bool
    /// Date survolée dans chaque graphique (`chartXSelection`), pour l'infobulle.
    @State private var hoveredTemperatureDate: Date?
    /// Repère du record de chaleur sur la carte : celui du parent en mode
    /// intégré (vue Département), le nôtre dans la fenêtre Climat.
    @Environment(\.recordPin) private var parentRecordPin
    @StateObject private var ownRecordPin = RecordPinModel()
    private var recordPin: RecordPinModel { embedded ? parentRecordPin : ownRecordPin }
    @State private var hoveredPrecipitationDate: Date?
    /// Regroupement des barres de précipitations : par mois ou par trimestre.
    @State private var rainGrouping: RainGrouping = .month
    let departementCode: String
    /// Mode intégré (vue Département de la sidebar) : sans en-tête, carte,
    /// défilement ni cadre de fenêtre — le parent les fournit.
    let embedded: Bool

    public init(departementCode: String, embedded: Bool = false) {
        self.departementCode = departementCode
        self.embedded = embedded
    }

    private static let calendar = MeteoMensuelle.calendar

    private var series: [MeteoMensuelle.Point] { MeteoMensuelle.series(forDepartementCode: departementCode) }

    private func year(_ p: MeteoMensuelle.Point) -> Int { Self.calendar.component(.year, from: p.date) }
    private func month(_ p: MeteoMensuelle.Point) -> Int { Self.calendar.component(.month, from: p.date) }
    private var years: [Int] { Array(Set(series.map(year))).sorted() }

    private func value(_ p: MeteoMensuelle.Point) -> Double? {
        switch metric {
        case .temperature: p.temperature
        case .maxTemperature: p.maxTemperature
        case .record: p.absoluteMax
        case .precipitation: p.precipitation
        }
    }

    private var unit: String { metric == .precipitation ? "mm" : "°C" }

    public var body: some View {
        OptionalScroll(enabled: !embedded) {
            VStack(alignment: .leading, spacing: 24) {
                if !embedded {
                    DepartementHeaderAndMap(departementCode: departementCode, state: state)
                }
                // Titre de section sous la carte ; en mode intégré (vue Département),
                // une ligne vide le sépare de la rubrique Culture qui précède.
                Eyebrow("Climat", color: c.ink, font: CFont.rounded(18, weight: .medium))
                    .padding(.top, embedded ? 22 : 0)
                    .padding(.bottom, -14)
                if series.isEmpty {
                    Text("Aucune donnée pour ce département.")
                        .font(CFont.rounded(13)).foregroundStyle(c.faint)
                } else {
                    let tempAxis = temperatureAxis
                    chartCard(title: "Températures moyennes, maximales et records mensuels (°C)", yTicks: tempAxis.ticks, footnote: Self.weightingNote) {
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
                                    .foregroundStyle(c.ink).symbolSize(90)
                                // Infobulle permanente sur le point le plus haut du mois
                                // sélectionné, pour chaque année.
                                PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", p.maxTemperature ?? p.temperature ?? 0))
                                    .foregroundStyle(c.ink).symbolSize(p.maxTemperature == nil ? 0 : 90)
                                recordHighlight(p)
                                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                        tooltip(p, value: "Moy. \(frDecimal(p.temperature ?? 0)) °C", secondary: temperatureLines(p))
                                    }
                            }
                            if let p = hoveredPoint(hoveredTemperatureDate, in: points), selectedMonth != month(p) {
                                highlightMarks(p)
                                RuleMark(x: .value("Mois", p.date, unit: .month))
                                    .foregroundStyle(c.faint.opacity(0.5))
                                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                        tooltip(p, value: "Moy. \(frDecimal(p.temperature ?? 0)) °C", secondary: temperatureLines(p))
                                    }
                            }
                        }
                        .chartForegroundStyleScale(["Moyenne": Color(hex: 0x5B9BD5), "Maximale": Color(hex: 0xE58A2A), "Record absolu": Color(hex: 0xD1382E)])
                        .chartXSelection(value: $hoveredTemperatureDate)
                        .chartGesture { proxy in monthTap(proxy, points: points) }
                        .chartYScale(domain: tempAxis.domain)
                    }
                    chartCard(title: rainGrouping == .month ? "Précipitations mensuelles (mm)" : "Précipitations trimestrielles (moyenne mensuelle du trimestre, mm)", trailing: { groupingButtons }) {
                        let points = series.filter { $0.precipitation != nil }
                        let quarters = rainQuarters
                        Chart {
                            yearBands
                            if rainGrouping == .month {
                                ForEach(points) { p in
                                    BarMark(x: .value("Mois", p.date, unit: .month), y: .value("mm", p.precipitation ?? 0))
                                        .foregroundStyle((selectedMonth == month(p) ? Color(hex: 0x1B3A5C) : Color(hex: 0x7EC8E3)).opacity(p.partial ? 0.4 : 0.8))
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
                                        .foregroundStyle(c.faint.opacity(0.5))
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
                                        .foregroundStyle(c.faint.opacity(0.5))
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
                        .font(CFont.rounded(11)).foregroundStyle(c.faint)
                }
            }
            .padding(embedded ? 0 : 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .departementDetailWindow(!embedded)
        .environment(\.recordPin, recordPin)
        // Flèches gauche/droite : mois précédent/suivant de la sélection
        // (graphiques et tableau), sans effet tant qu'aucun mois n'est
        // sélectionné.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            if !embedded { isFocused = true }
            updateRecordPins()
        }
        .onChange(of: selectedMonth) { _, new in
            updateRecordPins()
            if new != nil { isFocused = true } else { selectedYear = nil }
        }
        .onKeyPress(.leftArrow) { moveSelection(by: -1) }
        .onKeyPress(.rightArrow) { moveSelection(by: 1) }
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
                .symbol {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(hex: 0xD1382E))
                }
        }
    }

    /// Au survol d'un mois : moyenne, maximale et record mis en évidence ensemble.
    @ChartContentBuilder
    private func highlightMarks(_ p: MeteoMensuelle.Point) -> some ChartContent {
        PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", p.temperature ?? 0))
            .foregroundStyle(c.ink).symbolSize(90)
        if let tx = p.maxTemperature {
            PointMark(x: .value("Mois", p.date, unit: .month), y: .value("°C", tx))
                .foregroundStyle(c.ink).symbolSize(90)
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
                .foregroundStyle((y - years[0]) % 2 == 0 ? c.track.opacity(0.45) : .clear)
                .annotation(position: .overlay, alignment: .topLeading, spacing: 0) {
                    Text(String(y))
                        .font(CFont.rounded(11, weight: .bold)).foregroundStyle(c.ink)
                        .padding(.leading, 6).padding(.top, 3)
                }
        }
    }

    /// Repère sur la carte, par un soleil rouge, le relevé du record de chaleur
    /// du mois sélectionné pour chaque année : un repère par emplacement, avec
    /// la ou les années où le record y a été relevé.
    private func updateRecordPins() {
        guard let m = selectedMonth else { recordPin.marks = []; return }
        var order: [String] = []
        var byKey: [String: (coordinate: RecordPinCoordinate, years: [Int])] = [:]
        for p in series where month(p) == m {
            guard let location = p.absoluteMaxLocation else { continue }
            let key = "\(location.latitude),\(location.longitude)"
            if byKey[key] == nil { byKey[key] = (location, []); order.append(key) }
            byKey[key]?.years.append(year(p))
        }
        recordPin.marks = order.compactMap { byKey[$0] }.map { RecordPinMark(coordinate: $0.coordinate, years: $0.years.sorted()) }
    }

    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard let m = selectedMonth else { return .ignored }
        // Déplacement en boucle : décembre → janvier et janvier → décembre.
        selectedMonth = ((m - 1 + delta) % 12 + 12) % 12 + 1
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

    /// Lignes complémentaires de l'infobulle de température : maximale
    /// moyenne et record absolu (sans poste ni date).
    private func temperatureLines(_ p: MeteoMensuelle.Point) -> String {
        [p.maxTemperature.map { "Max. \(frDecimal($0)) °C" }, p.absoluteMax.map { "Record \(frDecimal($0)) °C" }]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private func tooltip(_ p: MeteoMensuelle.Point, value: String, secondary: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Self.monthFormatter.string(from: p.date).capitalized)
                .font(CFont.rounded(12, weight: .medium)).foregroundStyle(c.faint)
            Text(value).font(CFont.rounded(12, weight: .medium)).foregroundStyle(c.ink)
            if let secondary, !secondary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(secondary.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                        // Le nombre du record de température est en rouge.
                        if line.hasPrefix("Record ") {
                            Text("Record ").font(CFont.rounded(12, weight: .medium)).foregroundColor(c.ink)
                                + Text(line.dropFirst("Record ".count)).font(CFont.rounded(12, weight: .medium)).foregroundColor(Color(hex: 0xD1382E))
                        } else {
                            Text(line).font(CFont.rounded(12, weight: .medium)).foregroundStyle(c.ink)
                        }
                    }
                }
            }
            if p.partial { Text("mois en cours").font(CFont.rounded(12, weight: .medium)).foregroundStyle(c.faint2) }
        }
        .modifier(TooltipBox(c: c))
    }

    // MARK: Précipitations par trimestre

    private struct RainQuarter: Identifiable {
        let start: Date
        let end: Date
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
            return RainQuarter(start: start, end: end,
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
        let color: Color = selectedQuarterContains(q) ? Color(hex: 0x1B3A5C) : Color(hex: 0x7EC8E3)
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
                .font(CFont.rounded(12, weight: .medium)).foregroundStyle(c.faint)
            Text(verbatim: "\(frDecimal(q.mean)) mm/mois").font(CFont.rounded(12, weight: .medium)).foregroundStyle(c.ink)
            if q.partial {
                Text("trimestre en cours").font(CFont.rounded(12, weight: .medium)).foregroundStyle(c.faint2)
            } else if q.monthCount < 3 {
                Text("\(q.monthCount) mois disponibles").font(CFont.rounded(12, weight: .medium)).foregroundStyle(c.faint2)
            }
        }
        .modifier(TooltipBox(c: c))
    }

    /// Boutons Mois / Trimestres, dans le style des boutons Explorer / Satellite
    /// de la carte (capsule), remplie de la couleur d'accent quand actif.
    private var groupingButtons: some View {
        HStack(spacing: 8) {
            ForEach(RainGrouping.allCases) { g in
                Button { rainGrouping = g } label: {
                    Text(g.rawValue)
                        .font(CFont.rounded(12, weight: .medium))
                        .foregroundStyle(rainGrouping == g ? .white : c.ink)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(rainGrouping == g ? ClassicTheme.accent : .clear)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(rainGrouping == g ? ClassicTheme.accent : c.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(g == .month ? "Afficher les précipitations par mois" : "Afficher la moyenne mensuelle par trimestre")
            }
        }
    }

    /// Légende du graphique des températures : méthode de calcul de la valeur
    /// départementale (voir geo_pipeline/build_meteo_data.py).
    private static let weightingNote = "Température moyenne mensuelle : moyenne des postes de mesure du département, pondérée par la population. Chaque commune est rattachée au poste le plus proche ; un poste pèse le nombre d'habitants des communes qui lui sont rattachées, ce qui limite le poids des postes d'altitude, peu habités. La température maximale moyenne est pondérée de la même façon ; le record est celui du poste le plus chaud du département."

    private func chartCard<C: View>(title: String, yTicks: [Double]? = nil, footnote: String? = nil, @ViewBuilder chart: () -> C) -> some View {
        chartCard(title: title, yTicks: yTicks, footnote: footnote, trailing: { EmptyView() }, chart: chart)
    }

    private func chartCard<C: View, T: View>(title: String, yTicks: [Double]? = nil, footnote: String? = nil, @ViewBuilder trailing: () -> T, @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(title).font(CFont.rounded(13, weight: .medium)).foregroundStyle(c.ink)
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
                            AxisValueLabel().font(CFont.rounded(11)).foregroundStyle(c.faint)
                        }
                    } else {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel().font(CFont.rounded(11)).foregroundStyle(c.faint)
                        }
                    }
                }
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    // Repères mensuels discrets, trimestres nommés ; les années
                    // sont indiquées dans les bandes (voir `yearBands`).
                    AxisMarks(values: .stride(by: .month)) { value in
                        let m = value.as(Date.self).map { Self.calendar.component(.month, from: $0) } ?? 0
                        AxisTick(length: 3).foregroundStyle(c.faint2)
                        if m == 1 || m == 4 || m == 7 || m == 10 {
                            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                                .font(CFont.rounded(9)).foregroundStyle(c.faint)
                        }
                    }
                }
                .frame(height: 325)
            if let footnote {
                // Une ligne vide sépare la légende des pastilles de couleur du graphique.
                Text(footnote)
                    .font(CFont.rounded(11)).foregroundStyle(c.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
        .padding(16)
        .background(c.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.border, lineWidth: 1))
    }

    /// Par année civile : température moyenne et cumul de pluie sur les mois
    /// disponibles (première et dernière années partielles).
    private var yearlySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Moyennes annuelles").font(CFont.rounded(13, weight: .medium)).foregroundStyle(c.ink)
            HStack(spacing: 12) {
                ForEach(years, id: \.self) { y in
                    let pts = series.filter { year($0) == y }
                    let temps = pts.compactMap(\.temperature)
                    let rain = pts.compactMap(\.precipitation)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(y)).font(CFont.rounded(11, weight: .bold)).foregroundStyle(c.ink)
                            .padding(.bottom, 3)
                        HStack(spacing: 5) {
                            Image(systemName: "thermometer.medium").font(.system(size: 13)).foregroundStyle(ClassicTheme.accent)
                            Text(temps.isEmpty ? "–" : "\(frDecimal(temps.reduce(0, +) / Double(temps.count))) °C")
                                .font(CFont.rounded(16, weight: .semibold)).foregroundStyle(c.ink)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "cloud.rain").font(.system(size: 12)).foregroundStyle(ClassicTheme.accent)
                            Text(rain.isEmpty ? "–" : String(format: "%.0f mm", rain.reduce(0, +)))
                                .font(CFont.rounded(13)).foregroundStyle(c.sub)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedYear == y ? ClassicTheme.accent.opacity(0.12) : c.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedYear == y ? ClassicTheme.accent : c.border, lineWidth: selectedYear == y ? 1.5 : 1))
                }
            }
        }
        .padding(16)
        .background(c.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.border, lineWidth: 1))
    }

    /// Tableau mois (lignes) × années (colonnes), commutable entre
    /// températures et précipitations.
    private var monthTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Titre et boutons sur une seule ligne, alignés sur leur ligne de
            // base — le titre passe à la ligne s'il manque de place plutôt
            // que de pousser les boutons hors du cadre.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Détail par mois des températures (°C) et précipitations (mm)")
                    .font(CFont.rounded(13, weight: .medium)).foregroundStyle(c.ink)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                ForEach(Metric.allCases) { m in
                    let isOn = metric == m
                    Button { metric = m } label: {
                        Label(m.rawValue, systemImage: m.icon)
                            .font(CFont.rounded(12, weight: .medium))
                            .foregroundStyle(isOn ? Color.white : c.body)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(isOn ? ClassicTheme.accent : c.track.opacity(0.6), in: Capsule())
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                }
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("").frame(width: 110, alignment: .leading)
                    ForEach(years, id: \.self) {
                        Text(String($0)).font(CFont.rounded(11, weight: .bold)).foregroundStyle(c.ink)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
                Divider().padding(.bottom, 2)
                ForEach(1...12, id: \.self) { m in
                    let isSelected = selectedMonth == m
                    HStack(spacing: 0) {
                        Text(Self.monthName(m)).font(CFont.rounded(13, weight: isSelected ? .semibold : .regular)).foregroundStyle(c.body)
                            .frame(width: 110, alignment: .leading)
                        ForEach(years, id: \.self) { y in
                            let p = series.first { year($0) == y && month($0) == m }
                            Text(p.flatMap(value).map { metric == .precipitation ? String(format: "%.0f", $0) : frDecimal($0) } ?? "–")
                                .font(CFont.mono(12))
                                .foregroundStyle(p?.partial == true ? c.faint : c.ink)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(isSelected ? ClassicTheme.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    // Un clic sélectionne la ligne entière ; recliquer la désélectionne.
                    .onTapGesture { selectedMonth = isSelected ? nil : m }
                }
            }
            Text("Valeurs en \(unit).").font(CFont.rounded(11)).foregroundStyle(c.faint2)
        }
        .padding(16)
        .background(c.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.border, lineWidth: 1))
    }

    private static let monthNames = ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]
    private static func monthName(_ m: Int) -> String { monthNames[m - 1] }
}

/// Cadre des infobulles des graphiques (mois, trimestre).
private struct TooltipBox: ViewModifier {
    let c: DetailColors
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(c.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(c.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}
