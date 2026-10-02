import Foundation

/// Real per-département 0-100 scores for the 3 Culture criteria kept in
/// "Big Mac" (Musées, Lieux du patrimoine, Festivals), precomputed offline
/// from culture.data.gouv.fr datasets — see geo_pipeline/build_culture_data.py
/// and geo_pipeline/README.md. Mirrors `FranceGeoData`'s loading pattern.
enum CultureScores {
    struct DepartementScore: Decodable {
        let codeInsee: String
        let scores: [String: Double]
        /// Noms des sites/événements par critère ("musees", "patrimoine",
        /// "festivals", plus "spr" pour les sites patrimoniaux remarquables).
        let names: [String: [String]]
        /// Site officiel par critère puis par nom ("festivals" seulement :
        /// les données Basilic (musées) et SPR n'ont pas de site internet).
        let urls: [String: [String: String]]
        /// Discipline dominante par critère puis par nom ("festivals"
        /// seulement : les musées n'ont pas de variable thématique).
        let disciplines: [String: [String: String]]
    }

    private struct Root: Decodable {
        let generatedAt: String
        let departements: [DepartementScore]
    }

    /// Stable key order, matching the 3 Culture rows kept in `SelecteurView`.
    static let criterionKeys = ["musees", "patrimoine", "festivals"]

    private static let root: Root? = {
        guard let url = Bundle.module.url(forResource: "culture_scores", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Root.self, from: data)
    }()

    static let generatedAt: String? = root?.generatedAt

    /// Scores indexed by département code — avoids a linear scan of the 101
    /// départements for every lookup when combining with commune-size
    /// matching in `SelecteurView`.
    private static let byDepartementCode: [String: DepartementScore] = {
        Dictionary(uniqueKeysWithValues: (root?.departements ?? []).map { ($0.codeInsee, $0) })
    }()

    /// Scores triés de chaque critère, calculés une seule fois.
    private static let sortedScores: [String: [Double]] = Dictionary(uniqueKeysWithValues: criterionKeys.map { key in
        (key, byDepartementCode.values.compactMap { $0.scores[key] }.sorted())
    })

    /// Weighted match (0-100) of a département against 3 weights (0...5,
    /// same order as `criterionKeys`), by weighted average of its criterion
    /// scores — same convention as `FranceGeoData.weightedScore`. Missing
    /// data (no bundled score for that département) falls back to 50.0.
    static func weightedScore(forDepartementCode code: String, weights: [Int]) -> Double {
        guard let dep = byDepartementCode[code] else { return 50.0 }
        return weightedAverage(dep.scores, keys: criterionKeys, weights: weights)
    }

    /// Floor a département must clear on `key` to pass its hard filter at
    /// "déterminant" — the 85th percentile of that criterion's real score
    /// distribution, same convention as `FranceGeoData.hardFilterThreshold`.
    /// Only the top ~15% of départements pass once a Big Mac criterion
    /// (Musées/Lieux du patrimoine/Festivals) is pushed to "déterminant" —
    /// see `passesHardFilter`.
    static func hardFilterThreshold(forKey key: String, percentile: Double = FranceGeoData.determinantPercentile) -> Double? {
        sortedScores[key].flatMap { percentileValue($0, percentile) }
    }

    /// Whether the département at `code` passes the hard filter for `key`
    /// at `weight` — "important" (top ~40 %) and "déterminant" (top ~15 %)
    /// both filter, "indifférent" doesn't; same rule as
    /// `FranceGeoData.passesHardFilter`.
    static func passesHardFilter(forDepartementCode code: String, key: String, weight: Int, maxWeight: Int) -> Bool {
        guard let percentile = FranceGeoData.filterPercentile(forWeight: weight, maxWeight: maxWeight),
              let threshold = hardFilterThreshold(forKey: key, percentile: percentile),
              let dep = byDepartementCode[code] else { return true }
        return (dep.scores[key] ?? 50.0) >= threshold
    }

    /// Noms des sites/événements d'un critère ("musees", "patrimoine",
    /// "festivals") pour un département donné — utilisé par l'inspecteur
    /// pour lister le contenu culturel du département cliqué.
    static func names(forDepartementCode code: String, criterionKey: String) -> [String] {
        byDepartementCode[code]?.names[criterionKey] ?? []
    }

    /// Lien d'un site/événement : site officiel quand les données en
    /// fournissent un (festivals), sinon recherche web sur le nom. macOS
    /// n'expose pas d'API publique pour interroger le moteur de recherche
    /// par défaut d'une app tierce (seule Safari applique ce réglage à sa
    /// propre barre d'adresse) ; on utilise donc une recherche Google,
    /// ouverte via le navigateur par défaut du système.
    static func link(forDepartementCode code: String, criterionKey: String, name: String) -> URL? {
        if let site = byDepartementCode[code]?.urls[criterionKey]?[name].flatMap(URL.init(string:)) { return site }
        let query = titleCased(name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/search?q=\(query)")
    }

    /// Les Micro-Folies (réseau de petits équipements numériques, distinct
    /// des musées classiques) sont reléguées en fin de liste des musées.
    static func isMicroFolie(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("micro-folie") || name.localizedCaseInsensitiveContains("microfolie")
    }

    /// Festivals regroupés par discipline dominante (les plus fournies
    /// d'abord), festivals sans discipline ("Autre") en dernier.
    static func festivalsByDiscipline(forDepartementCode code: String, names: [String]) -> [(discipline: String, names: [String])] {
        let byDiscipline = Dictionary(grouping: names) {
            byDepartementCode[code]?.disciplines["festivals"]?[$0] ?? "Autre"
        }
        return byDiscipline
            .map { (discipline: $0.key, names: $0.value) }
            .sorted {
                if $0.discipline == "Autre" || $1.discipline == "Autre" { return $1.discipline == "Autre" && $0.discipline != "Autre" }
                return $0.names.count != $1.names.count ? $0.names.count > $1.names.count : $0.discipline < $1.discipline
            }
    }

    // MARK: Noms affichés

    /// Prépositions/articles français qui restent en minuscules dans une
    /// casse de titre, sauf en position initiale (ex. "Château de Chambord",
    /// mais "Le Havre").
    private static let lowercasedParticles: Set<String> = [
        "de", "du", "des", "d'", "la", "le", "les", "l'", "et", "en", "à", "au", "aux", "sur"
    ]

    /// Les noms bruts mélangent TOUT MAJUSCULES et tout minuscules — on les
    /// remet en casse de titre (mot par mot, prépositions/articles en
    /// minuscules sauf en premier mot) pour un affichage cohérent. Simplifié :
    /// suffisant pour des noms de lieux/événements affichés en liste, sans
    /// prétendre à une capitalisation typographique parfaite (ex. les
    /// apostrophes type "d'Azur" ne sont pas toutes détectées).
    /// Élisions françaises ("d'", "l'", "n'", "j'", "c'", "m'", "t'", "s'",
    /// "qu'") collées au mot suivant (ex. "d'Histoire", "l'Aventure") — la
    /// particule reste en minuscule (sauf en tout premier mot), la lettre
    /// après l'apostrophe se capitalise comme un mot normal.
    private static let elisionPrefixes = ["qu'", "d'", "l'", "n'", "j'", "c'", "m'", "t'", "s'"]

    /// Élisions sans apostrophe : certaines sources (ex. le CSV des sites
    /// patrimoniaux remarquables) séparent la particule élidée par une
    /// espace au lieu d'une apostrophe collée ("ST SYMPHORIEN D OZON" plutôt
    /// que "St Symphorien d'Ozon"), ce qui fait capitaliser le "D" comme un
    /// mot à part entière. On rejoint ces mots isolés au suivant avec une
    /// apostrophe avant la casse de titre normale.
    private static let standaloneElisionLetters: Set<String> = ["d", "l", "n", "j", "c", "m", "t", "s", "qu"]

    private static func mergeStandaloneElisions(_ words: [Substring]) -> [String] {
        var merged: [String] = []
        var i = 0
        while i < words.count {
            let word = String(words[i])
            if standaloneElisionLetters.contains(word), i + 1 < words.count {
                merged.append(word + "'" + words[i + 1])
                i += 2
            } else {
                merged.append(word)
                i += 1
            }
        }
        return merged
    }

    static func titleCased(_ name: String) -> String {
        let words = mergeStandaloneElisions(name.lowercased().split(separator: " "))
        return words.enumerated().map { index, word -> String in
            if index > 0, lowercasedParticles.contains(word) { return word }
            if let prefix = elisionPrefixes.first(where: { word.hasPrefix($0) }), word.count > prefix.count {
                let rest = word.dropFirst(prefix.count)
                let capitalizedRest = rest.prefix(1).uppercased() + rest.dropFirst()
                // Premier mot : la particule elle-même se capitalise aussi
                // (ex. "D'Histoire naturelle du Muséum").
                return (index == 0 ? prefix.prefix(1).uppercased() + prefix.dropFirst() : prefix) + capitalizedRest
            }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// Déduplique les noms bruts : d'abord les doublons exacts (ex. deux
    /// sites patrimoniaux distincts d'une même commune s'affichent tous les
    /// deux sous le simple nom de la commune, ex. "Lyon" en double dans le
    /// Rhône), puis, pour les musées uniquement (`mergeVariants`), les
    /// variantes où un nom est entièrement contenu dans un autre (ex.
    /// "Musée des Confluences" / "Muséum - Musée des Confluences") — on
    /// garde alors le plus court des deux, jugé le nom usuel.
    static func dedupedNames(_ names: [String], mergeVariants: Bool) -> [String] {
        var exactDeduped: [String] = []
        var seenTitleCased = Set<String>()
        for name in names where seenTitleCased.insert(titleCased(name)).inserted {
            exactDeduped.append(name)
        }
        guard mergeVariants else { return exactDeduped }

        // Noms retenus et leur casse de titre, calculée une seule fois.
        var result: [(name: String, key: String)] = []
        for name in exactDeduped {
            let candidate = titleCased(name)
            if let existingIndex = result.firstIndex(where: { existing in
                existing.key.localizedCaseInsensitiveContains(candidate) || candidate.localizedCaseInsensitiveContains(existing.key)
            }) {
                // Garde la variante la plus courte des deux.
                if name.count < result[existingIndex].name.count { result[existingIndex] = (name, candidate) }
            } else {
                result.append((name, candidate))
            }
        }
        return result.map(\.name)
    }

    /// Tri alphabétique sur le nom affiché (casse de titre calculée une fois
    /// par nom, pas à chaque comparaison).
    static func sortedByTitle(_ names: [String]) -> [String] {
        names.map { (name: $0, key: titleCased($0)) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.name)
    }
}
