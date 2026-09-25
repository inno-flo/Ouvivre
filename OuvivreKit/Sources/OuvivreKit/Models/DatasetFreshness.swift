import Foundation

/// Périodiquement (au plus une fois tous les 15 jours), vérifie si les 4
/// jeux de données open data bundlés (communes, musées/Basilic, sites
/// patrimoniaux remarquables, festivals) ont été mis à jour côté
/// data.gouv.fr depuis leur dernier traitement offline par `geo_pipeline/`.
///
/// L'app ne relance jamais le pipeline elle-même — ce reste un workflow
/// manuel (voir `geo_pipeline/README.md`) — cette classe se contente de
/// signaler qu'un nouveau run serait utile. C'est le seul appel réseau de
/// l'app ; en cas d'échec (hors ligne, timeout, API indisponible), il
/// échoue silencieusement et ne bloque rien.
@MainActor
public final class DatasetFreshness: ObservableObject {
    public struct Dataset {
        public let id: String
        public let label: String
        public let generatedAt: Date?
    }

    /// Libellés des jeux de données bundlés qui se sont révélés plus récents
    /// côté data.gouv.fr que la dernière génération offline — vide tant que
    /// rien n'est à jour ou que la vérification n'a pas encore eu lieu.
    @Published public private(set) var staleDatasets: [String] = []
    @Published public private(set) var lastCheckedAt: Date?

    private static let lastCheckedKey = "DatasetFreshness.lastCheckedAt"
    private static let checkInterval: TimeInterval = 15 * 24 * 3600

    public init() {
        lastCheckedAt = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseGeneratedAt(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let d = isoFormatter.date(from: string) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: string) { return d }
        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd"
        simple.timeZone = TimeZone(identifier: "UTC")
        return simple.date(from: string)
    }

    /// Les 4 jeux de données à surveiller, avec leur id data.gouv.fr et la
    /// date `generatedAt` actuellement bundlée dans OuvivreKit.
    private func bundledDatasets() -> [Dataset] {
        let communesGeneratedAt = Self.readGeneratedAt(resource: "communes_data")
        let cultureGeneratedAt = Self.readGeneratedAt(resource: "culture_scores")
        return [
            Dataset(id: "6745d9ae4524d845d2138193", label: "Communes de France", generatedAt: communesGeneratedAt),
            Dataset(id: "61777ddaa9101d073e5506cd", label: "Musées (Basilic)", generatedAt: cultureGeneratedAt),
            Dataset(id: "628da9ff836d8bf454c7fd48", label: "Lieux du patrimoine (SPR)", generatedAt: cultureGeneratedAt),
            Dataset(id: "62cf95993d99f22480f49334", label: "Festivals", generatedAt: cultureGeneratedAt),
        ]
    }

    private static func readGeneratedAt(resource: String) -> Date? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let generatedAt = obj["generatedAt"] as? String else { return nil }
        return parseGeneratedAt(generatedAt)
    }

    /// Vérifie la fraîcheur des jeux de données auprès de l'API data.gouv.fr,
    /// mais seulement si la dernière vérification remonte à 15 jours ou plus
    /// — pour ne jamais appeler l'API plus d'une fois par quinzaine. Échoue
    /// silencieusement (pas de crash, pas d'erreur visible) si hors ligne.
    public func checkIfDue() async {
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.checkInterval {
            return
        }

        var stale: [String] = []
        var anySucceeded = false
        for dataset in bundledDatasets() {
            guard let upstream = await Self.fetchLastModified(datasetId: dataset.id) else { continue }
            anySucceeded = true
            if let generatedAt = dataset.generatedAt, upstream > generatedAt {
                stale.append(dataset.label)
            }
        }

        // Hors ligne (ou API en panne) : on ne mémorise pas la vérification,
        // pour réessayer au prochain affichage plutôt que dans 15 jours.
        guard anySucceeded else { return }
        staleDatasets = stale
        lastCheckedAt = Date()
        UserDefaults.standard.set(lastCheckedAt, forKey: Self.lastCheckedKey)
    }

    private static func fetchLastModified(datasetId: String) async -> Date? {
        guard let url = URL(string: "https://www.data.gouv.fr/api/1/datasets/\(datasetId)/") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lastModified = obj["last_modified"] as? String else { return nil }
            return parseGeneratedAt(lastModified)
        } catch {
            return nil
        }
    }
}
