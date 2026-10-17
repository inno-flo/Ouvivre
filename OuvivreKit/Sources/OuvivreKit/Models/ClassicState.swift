import SwiftUI

enum ClassicScreen {
    case selecteur, sources, favoris
}

/// Destination de la sidebar : une rubrique, ou la vue d'un département favori.
enum SidebarDestination: Hashable {
    case screen(ClassicScreen)
    case departement(String)
}

/// Root app state — mirrors the dc export's `Component` state/logic:
/// current screen, country, and the proximity/Culture weight sliders
/// (0...2), all mutated in place and re-derived on read.
@MainActor
final class ClassicState: ObservableObject {
    /// Échelle des réglettes du Sélecteur (proximités et Culture) :
    /// indifférent (0), important (1), déterminant (2).
    nonisolated static let maxWeight = 2

    @Published var screen: ClassicScreen = .selecteur
    /// Code INSEE du département favori affiché (vue Département), sinon `nil`.
    @Published var selectedDepartementCode: String?
    @Published var country: String = "France"
    /// Géographie 2's own weights, on its 3-level (0...2) scale.
    @Published var geo2: [Int] = ClassicStatic.geo.map { _ in 0 }
    @Published var excludeOverseas: Bool = false
    @Published var excludeCorse: Bool = false
    /// Filtres de taille de commune pour "Big Mac" (Block 2) — tout
    /// désélectionné par défaut au premier lancement, l'utilisateur choisit
    /// activement les tailles qui l'intéressent.
    @Published var communeSizes: Set<CommuneSizeCategory> = []
    /// Ouverture/fermeture des blocs "Big Mac" — dans `ClassicState`
    /// plutôt qu'en `@State` sur `SelecteurView` pour persister quand on quitte
    /// puis revient sur cet écran (un seul bloc ouvert par défaut : Pays).
    @Published var bigMacExpandedPays: Bool = true
    @Published var bigMacExpandedRegions: Bool = false
    /// Codes INSEE des départements mis en favori depuis l'inspecteur,
    /// persistés dans `UserDefaults` entre les lancements.
    @Published var favoriteDepartementCodes: Set<String> = ClassicState.storedFavorites {
        didSet { UserDefaults.standard.set(Array(favoriteDepartementCodes).sorted(), forKey: Self.favoritesKey) }
    }
    /// Poids des 3 critères Culture repris par "Big Mac" (Musées, Lieux du
    /// patrimoine, Festivals), dans l'ordre de `CultureScores.criterionKeys` —
    /// démarrent à 0 (indifférent).
    @Published var culture: [Int] = ClassicStatic.culture.map { _ in 0 }

    private static let favoritesKey = "favoriteDepartementCodes"
    private static var storedFavorites: Set<String> { Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []) }
    private var favoritesObserver: NSObjectProtocol?

    init() {
        // Les favoris sont partagés entre instances (fenêtre principale et
        // fenêtre de détail météo, chacune avec sa propre `ClassicState`) via
        // `UserDefaults` : on recharge quand une autre instance les modifie.
        favoritesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let stored = Self.storedFavorites
                if stored != self.favoriteDepartementCodes { self.favoriteDepartementCodes = stored }
            }
        }
    }

    deinit {
        if let favoritesObserver { NotificationCenter.default.removeObserver(favoritesObserver) }
    }

    func go(_ screen: ClassicScreen) { self.screen = screen; selectedDepartementCode = nil }

    func goToDepartement(_ code: String) { selectedDepartementCode = code }

    func resetGeo2() { geo2 = ClassicStatic.geo.map { _ in 0 } }

    func resetCulture() { culture = ClassicStatic.culture.map { _ in 0 } }

    func setGeo2(_ index: Int, value: Int) { geo2[index] = max(0, min(Self.maxWeight, value)) }

    func setCulture(_ index: Int, value: Int) {
        // Différé au prochain tick : appelé en direct depuis le
        // `DragGesture.onChanged` de `CriterionRow`, muter `culture`
        // (@Published) pendant que SwiftUI traite encore la mise à jour de
        // vue en cours déclenche "Publishing changes from within view
        // updates is not allowed" — observé sur les réglettes Culture de
        // Big Mac, dont le `.onChange(of: state.culture)` redessine aussitôt
        // les départements pendant le même cycle.
        let clamped = max(0, min(Self.maxWeight, value))
        DispatchQueue.main.async { [weak self] in
            self?.culture[index] = clamped
        }
    }

    func toggleFavoriteDepartement(_ code: String) {
        setFavorite(code, isOn: !favoriteDepartementCodes.contains(code), undoManager: nil)
    }

    /// Ajoute ou retire un favori en enregistrant l'inverse auprès de
    /// l'`UndoManager` de la fenêtre : Édition > Annuler / Rétablir.
    func setFavorite(_ code: String, isOn: Bool, undoManager: UndoManager?) {
        if isOn { favoriteDepartementCodes.insert(code) } else { favoriteDepartementCodes.remove(code) }
        undoManager?.registerUndo(withTarget: self) { state in
            MainActor.assumeIsolated { state.setFavorite(code, isOn: !isOn, undoManager: undoManager) }
        }
        undoManager?.setActionName(isOn ? "Ajout aux favoris" : "Retrait des favoris")
    }

    // MARK: Valeurs dérivées (miroir de `renderVals()` dans l'export dc)

    var countryFacts: [LabeledValue] {
        ClassicStatic.countryProfiles[country]?.facts ?? []
    }

    /// Critères sans données pour le pays sélectionné (voir
    /// `ClassicStatic.hiddenCriteria`).
    private var hiddenCriteria: Set<String> { ClassicStatic.hiddenCriteria[country] ?? [] }

    /// Poids de proximité réellement appliqués : ceux des critères masqués
    /// pour le pays comptent pour 0, même s'ils restent réglés côté France.
    var effectiveGeo2: [Int] {
        zip(FranceGeoData.criterionKeys, geo2).map { hiddenCriteria.contains($0.0) ? 0 : $0.1 }
    }

    /// Poids Culture réellement appliqués (critères masqués à 0).
    var effectiveCulture: [Int] {
        zip(CultureScores.criterionKeys, culture).map { hiddenCriteria.contains($0.0) ? 0 : $0.1 }
    }

    /// Géographie 2's rows, on its own 3-level (0...2) scale — "souhaitable" et "accessoire" fusionnés dans "important".
    /// Les critères masqués pour le pays n'ont pas de réglette ; les `id`
    /// restent les index dans `geo2`.
    var geo2Rows: [WeightedRow] {
        ClassicStatic.geo.enumerated()
            .filter { !hiddenCriteria.contains(FranceGeoData.criterionKeys[$0.offset]) }
            .map { WeightedRow(id: $0.offset, label: $0.element, value: geo2[$0.offset]) }
    }

    /// Les 3 réglettes Culture, mêmes 3 niveaux que "Proximités" — sources :
    /// - Musées : https://culture.data.gouv.fr/datasets/61777ddaa9101d073e5506cd
    /// - Lieux du patrimoine : https://culture.data.gouv.fr/datasets/628da9ff836d8bf454c7fd48
    /// - Festivals : https://culture.data.gouv.fr/datasets/62cf95993d99f22480f49334
    var cultureRows: [WeightedRow] {
        ClassicStatic.culture.enumerated()
            .filter { !hiddenCriteria.contains(CultureScores.criterionKeys[$0.offset]) }
            .map { WeightedRow(id: $0.offset, label: $0.element, value: culture[$0.offset]) }
    }

    /// Les critères Culture dont le réglage est au-dessus de 0 (différent
    /// d'"Indifférent"), avec la clé `CultureScores.criterionKeys`
    /// correspondante — utilisé par l'inspecteur pour lister les critères
    /// actifs et le contenu culturel du département cliqué.
    var activeCultureCriteria: [(label: String, key: String)] {
        zip(zip(ClassicStatic.culture, CultureScores.criterionKeys), effectiveCulture)
            .filter { $0.1 > 0 }
            .map { (label: $0.0.0, key: $0.0.1) }
    }

    /// Real département scores (weighted by `geo2`), ranked — backed by
    /// `FranceGeoData` (IGN-derived, see geo_pipeline/). Replaces the old
    /// fake `topScore = 60 + geoSum*1.6` formula. Limité au pays sélectionné
    /// (départements français ou kommuner danoises).
    func rankedDepartements() -> [(dep: FranceGeoData.DepartementScore, score: Double)] {
        let weights = effectiveGeo2
        let maxWeight = Self.maxWeight
        // Hard-filtered criteria (see `FranceGeoData.hardFilterCriteria`) get
        // an eligibility floor on top of the weighted average below — a
        // weight alone can't make "déterminant" mean "only départements
        // that actually touch a coast/border".
        let hardFilterWeights: [(key: String, weight: Int)] = zip(FranceGeoData.criterionKeys, weights)
            .filter { FranceGeoData.hardFilterCriteria.contains($0.0) }
            .map { (key: $0.0, weight: $0.1) }
        // "pays étranger" gets its own km-based filter (see
        // `FranceGeoData.maxPaysEtrangerKm`) rather than the score-band one
        // above — its score is a compressed continuous distance, not a
        // handful of discrete buckets like "mer".
        let paysEtrangerWeight = FranceGeoData.criterionKeys.firstIndex(of: "paysEtranger").map { weights[$0] } ?? 0
        let activeFilterCount = hardFilterWeights.filter { $0.weight > 0 }.count + (paysEtrangerWeight > 0 ? 1 : 0)
        let allowedMisses = FranceGeoData.allowedMisses(activeFilterCount: activeFilterCount)
        return FranceGeoData.departements
            .filter { $0.country == country }
            .filter { !(excludeOverseas && $0.isOverseas) && !(excludeCorse && $0.isCorse) }
            // Un ou deux critères réglés s'appliquent en ET strict ; au-delà,
            // un raté est toléré (deux à partir de 5 critères), sinon leurs
            // exigences se concurrencent au point de tout éliminer — voir
            // `FranceGeoData.allowedMisses`.
            .filter { dep in
                let misses = hardFilterWeights.filter {
                    !FranceGeoData.passesHardFilter(dep, key: $0.key, weight: $0.weight, maxWeight: maxWeight)
                }.count + (FranceGeoData.passesPaysEtrangerFilter(dep, weight: paysEtrangerWeight, maxWeight: maxWeight) ? 0 : 1)
                return misses <= allowedMisses
            }
            .map { ($0, FranceGeoData.weightedScore($0, weights: weights)) }
            .sorted { $0.1 > $1.1 }
    }
}
