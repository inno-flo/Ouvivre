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
final class DatasetFreshness: ObservableObject {
    struct Dataset {
        let id: String
        let label: String
        let generatedAt: Date?
    }

    /// Libellés des jeux de données bundlés qui se sont révélés plus récents
    /// côté data.gouv.fr que la dernière génération offline — vide tant que
    /// rien n'est à jour ou que la vérification n'a pas encore eu lieu.
    @Published private(set) var staleDatasets: [String] = UserDefaults.standard.stringArray(forKey: DatasetFreshness.staleKey) ?? []

    /// Libellés des jeux en cours de vérification.
    @Published private(set) var checkingLabels: Set<String> = []
    var isChecking: Bool { !checkingLabels.isEmpty }
    /// Date de la dernière vérification réussie, par jeu de données.
    @Published private(set) var verifiedAt: [String: Date] =
        UserDefaults.standard.dictionary(forKey: DatasetFreshness.verifiedKey) as? [String: Date] ?? [:]
    private static let verifiedKey = "DatasetFreshness.verifiedAt"
    /// Jeux dont la dernière vérification a été lancée à la main (sinon : automatique).
    @Published private(set) var manuallyVerified: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: DatasetFreshness.manualKey) ?? [])
    private static let manualKey = "DatasetFreshness.manuallyVerified"

    /// Instance partagée : la sidebar (pastille) et la vue Sources (tableau).
    static let shared = DatasetFreshness()
    private static let staleKey = "DatasetFreshness.staleDatasets"
    private var lastCheckedAt = UserDefaults.standard.object(forKey: DatasetFreshness.lastCheckedKey) as? Date

    private static let lastCheckedKey = "DatasetFreshness.lastCheckedAt"
    private static let checkInterval: TimeInterval = 15 * 24 * 3600

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterNoFraction = ISO8601DateFormatter()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }

    /// Les 4 jeux de données à surveiller, avec leur id data.gouv.fr et la
    /// date `generatedAt` actuellement bundlée dans OuvivreKit.
    static let datasets: [Dataset] = {
        let communesGeneratedAt = parseDate(CommuneSizeData.generatedAt)
        let cultureGeneratedAt = parseDate(CultureScores.generatedAt)
        return [
            Dataset(id: "6745d9ae4524d845d2138193", label: "Communes de France", generatedAt: communesGeneratedAt),
            Dataset(id: "61777ddaa9101d073e5506cd", label: "Musées (Basilic)", generatedAt: cultureGeneratedAt),
            Dataset(id: "628da9ff836d8bf454c7fd48", label: "Lieux du patrimoine (SPR)", generatedAt: cultureGeneratedAt),
            Dataset(id: "62cf95993d99f22480f49334", label: "Festivals", generatedAt: cultureGeneratedAt),
        ]
    }()

    /// Vérifie la fraîcheur des jeux de données auprès de l'API data.gouv.fr,
    /// mais seulement si la dernière vérification remonte à 15 jours ou plus
    /// — pour ne jamais appeler l'API plus d'une fois par quinzaine. Échoue
    /// silencieusement (pas de crash, pas d'erreur visible) si hors ligne.
    func checkIfDue() async {
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.checkInterval {
            return
        }
        await runCheck(manual: false)
    }

    /// Force la vérification, sans tenir compte du délai de 15 jours.
    func forceCheck() async {
        await runCheck(manual: true)
    }

    private func runCheck(manual: Bool) async {
        guard checkingLabels.isEmpty else { return }
        checkingLabels = Set(Self.datasets.map(\.label))
        defer { checkingLabels = [] }

        var stale: [String] = []
        var anySucceeded = false
        for dataset in Self.datasets {
            let upstream = await Self.fetchLastModified(datasetId: dataset.id)
            checkingLabels.remove(dataset.label)
            guard let upstream else { continue }
            anySucceeded = true
            verifiedAt[dataset.label] = Date()
            if manual { manuallyVerified.insert(dataset.label) } else { manuallyVerified.remove(dataset.label) }
            if let generatedAt = dataset.generatedAt, upstream > generatedAt {
                stale.append(dataset.label)
            }
        }

        // Hors ligne (ou API en panne) : on ne mémorise pas la vérification,
        // pour réessayer au prochain affichage plutôt que dans 15 jours.
        guard anySucceeded else { return }
        staleDatasets = stale
        UserDefaults.standard.set(stale, forKey: Self.staleKey)
        UserDefaults.standard.set(verifiedAt, forKey: Self.verifiedKey)
        UserDefaults.standard.set(Array(manuallyVerified), forKey: Self.manualKey)
        lastCheckedAt = Date()
        UserDefaults.standard.set(lastCheckedAt, forKey: Self.lastCheckedKey)
    }

    private static func fetchLastModified(datasetId: String) async -> Date? {
        guard let url = URL(string: "https://www.data.gouv.fr/api/1/datasets/\(datasetId)/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] else { return nil }
        return parseDate(obj["last_modified"] as? String)
    }
}
