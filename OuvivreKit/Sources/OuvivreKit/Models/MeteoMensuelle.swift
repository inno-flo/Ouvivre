import Foundation

/// Températures et précipitations mensuelles par département sur les 5
/// dernières années glissantes, précomputées offline depuis les données
/// climatologiques mensuelles de Météo-France — voir
/// geo_pipeline/build_meteo_data.py. Mirrors `CultureScores`' loading pattern.
enum MeteoMensuelle {
    struct Point: Identifiable {
        /// Premier jour du mois (fuseau UTC, pour un axe temporel stable).
        let date: Date
        /// Température moyenne du mois (°C), moyenne des postes du département.
        let temperature: Double?
        /// Moyenne des températures maximales quotidiennes du mois (°C).
        let maxTemperature: Double?
        /// Maximum absolu du mois (°C) dans le département.
        let absoluteMax: Double?
        /// Minimum absolu du mois (°C) dans le département (record de froid).
        let absoluteMin: Double?
        /// Cumul de précipitations du mois (mm), moyenne des postes.
        let precipitation: Double?
        /// Mois en cours : les valeurs ne couvrent pas le mois entier.
        let partial: Bool
        var id: Date { date }
    }

    private struct RawPoint: Decodable {
        let tm: Double?
        let tx: Double?
        let xa: Double?
        let na: Double?
        let rr: Double?
        let partial: Bool?
    }

    private struct Root: Decodable {
        let departements: [String: [String: RawPoint]]
    }

    /// Calendrier grégorien UTC, pour un axe temporel stable (partagé par
    /// l'inspecteur et la fenêtre Météo).
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// "AAAAMM" → premier jour du mois.
    private static func monthStart(_ key: String) -> Date? {
        guard key.count == 6, let year = Int(key.prefix(4)), let month = Int(key.suffix(2)) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    /// Série mensuelle triée chronologiquement, indexée par code département.
    private static let seriesByCode: [String: [Point]] = {
        guard let url = Bundle.module.url(forResource: "meteo_monthly", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else { return [:] }
        return root.departements.mapValues { months in
            months.compactMap { key, raw -> Point? in
                guard let date = monthStart(key) else { return nil }
                return Point(date: date, temperature: raw.tm, maxTemperature: raw.tx, absoluteMax: raw.xa, absoluteMin: raw.na, precipitation: raw.rr, partial: raw.partial ?? false)
            }
            .sorted { $0.date < $1.date }
        }
    }()

    /// Mois disponibles pour un département — vide si Météo-France n'en
    /// publie pas (ex. Mayotte).
    static func series(forDepartementCode code: String) -> [Point] {
        seriesByCode[code] ?? []
    }
}
