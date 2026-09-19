import Foundation

/// Températures et précipitations mensuelles par département sur les 5
/// dernières années glissantes, précomputées offline depuis les données
/// climatologiques mensuelles de Météo-France — voir
/// geo_pipeline/build_meteo_data.py. Mirrors `CultureScores`' loading pattern.
public enum MeteoMensuelle {
    public struct Point: Identifiable {
        /// Premier jour du mois (fuseau UTC, pour un axe temporel stable).
        public let date: Date
        /// Température moyenne du mois (°C), moyenne des postes du département.
        public let temperature: Double?
        /// Cumul de précipitations du mois (mm), moyenne des postes.
        public let precipitation: Double?
        /// Mois en cours : les valeurs ne couvrent pas le mois entier.
        public let partial: Bool
        public var id: Date { date }
    }

    private struct RawPoint: Decodable {
        let tm: Double?
        let rr: Double?
        let partial: Bool?
    }

    private struct Root: Decodable {
        let generatedAt: String
        let source: String
        let departements: [String: [String: RawPoint]]
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let root: Root? = {
        guard let url = Bundle.module.url(forResource: "meteo_monthly", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Root.self, from: data)
    }()

    public static let generatedAt: String? = root?.generatedAt
    public static let source: String? = root?.source

    /// "AAAAMM" → premier jour du mois.
    private static func monthStart(_ key: String) -> Date? {
        guard key.count == 6, let year = Int(key.prefix(4)), let month = Int(key.suffix(2)) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    /// Série mensuelle triée chronologiquement, indexée par code département.
    private static let seriesByCode: [String: [Point]] = {
        guard let root else { return [:] }
        return root.departements.mapValues { months in
            months.compactMap { key, raw -> Point? in
                guard let date = monthStart(key) else { return nil }
                return Point(date: date, temperature: raw.tm, precipitation: raw.rr, partial: raw.partial ?? false)
            }
            .sorted { $0.date < $1.date }
        }
    }()

    /// Mois disponibles pour un département — vide si Météo-France n'en
    /// publie pas (ex. Mayotte).
    public static func series(forDepartementCode code: String) -> [Point] {
        seriesByCode[code] ?? []
    }
}
