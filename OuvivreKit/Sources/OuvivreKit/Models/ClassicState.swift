import SwiftUI

public enum ClassicScreen: String, CaseIterable, Identifiable, Hashable {
    case pays, geo, geo2, bigMac, bigMacTests, meteo, affiner, ville, sources, favoris, favorisTests
    public var id: Self { self }
}

/// Root app state — mirrors the dc export's `Component` state/logic:
/// current screen, country query, and the geo/meteo/groups weight sliders
/// (0...5), all mutated in place and re-derived on read.
@MainActor
public final class ClassicState: ObservableObject {
    @Published public var screen: ClassicScreen = .bigMac
    @Published public var country: String = "France"
    @Published public var query: String = "France"
    @Published public var geo: [Int] = ClassicStatic.geo.map(\.1)
    /// Géographie 2's own weights, on its 5-level (0...4) scale.
    @Published public var geo2: [Int] = ClassicStatic.geo.map { _ in 0 }
    @Published public var excludeOverseas: Bool = false
    @Published public var excludeCorse: Bool = false
    /// Filtres de taille de commune pour "Big Mac" (Block 2) — tout
    /// désélectionné par défaut au premier lancement, l'utilisateur choisit
    /// activement les tailles qui l'intéressent.
    @Published public var includeVillage: Bool = false
    @Published public var includePetiteVille: Bool = false
    @Published public var includeVilleMoyenne: Bool = false
    @Published public var includeGrandeVille: Bool = false
    /// Ouverture/fermeture des 4 blocs "Big Mac" — dans `ClassicState`
    /// plutôt qu'en `@State` sur `BigMacView` pour persister quand on quitte
    /// puis revient sur cet écran (un seul bloc ouvert par défaut : Pays).
    @Published public var bigMacExpandedPays: Bool = true
    @Published public var bigMacExpandedRegions: Bool = false
    @Published public var bigMacExpandedCulture: Bool = false
    @Published public var bigMacExpandedMobilite: Bool = false
    /// Codes INSEE des départements mis en favori depuis l'inspecteur,
    /// persistés dans `UserDefaults` entre les lancements.
    @Published public var favoriteDepartementCodes: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favoriteDepartementCodes") ?? []) {
        didSet { UserDefaults.standard.set(Array(favoriteDepartementCodes).sorted(), forKey: "favoriteDepartementCodes") }
    }
    @Published public var meteo: [Int] = ClassicStatic.meteo.map(\.1)
    /// One weight array per group, indexed like `ClassicStatic.groups`. Les 3
    /// critères CULTURE repris par "Big Mac" (Musées, Lieux du patrimoine,
    /// Festivals) démarrent à 0 (indifférent) plutôt qu'avec les valeurs
    /// pré-remplies de `ClassicStatic` — celles-ci restent utilisées telles
    /// quelles par "Communes et services" pour les 4 autres critères CULTURE.
    @Published public var groups: [[Int]] = {
        var groups = ClassicStatic.groups.map { $0.rows.map(\.1) }
        if let cultureIndex = ClassicStatic.groups.firstIndex(where: { $0.title == "CULTURE" }) {
            let zeroedLabels: Set<String> = ["Musées", "Lieux du patrimoine", "Festivals"]
            for (rowIndex, row) in ClassicStatic.groups[cultureIndex].rows.enumerated() where zeroedLabels.contains(row.0) {
                groups[cultureIndex][rowIndex] = 0
            }
        }
        return groups
    }()

    private var favoritesObserver: NSObjectProtocol?

    public init() {
        // Les favoris sont partagés entre instances (fenêtre principale et
        // fenêtre de détail météo, chacune avec sa propre `ClassicState`) via
        // `UserDefaults` : on recharge quand une autre instance les modifie.
        favoritesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let stored = Set(UserDefaults.standard.stringArray(forKey: "favoriteDepartementCodes") ?? [])
                if stored != self.favoriteDepartementCodes { self.favoriteDepartementCodes = stored }
            }
        }
    }

    deinit {
        if let favoritesObserver { NotificationCenter.default.removeObserver(favoritesObserver) }
    }

    public func go(_ screen: ClassicScreen) { self.screen = screen }

    public func resetGeo() { geo = ClassicStatic.geo.map(\.1) }
    public func resetGeo2() { geo2 = ClassicStatic.geo.map { _ in 0 } }

    public func setGeo(_ index: Int, value: Int) { geo[index] = max(0, min(5, value)) }
    public func setGeo2(_ index: Int, value: Int) { geo2[index] = max(0, min(2, value)) }
    public func setMeteo(_ index: Int, value: Int) { meteo[index] = max(0, min(5, value)) }
    public func setGroup(_ groupIndex: Int, _ rowIndex: Int, value: Int) {
        // Différé au prochain tick : appelé en direct depuis le
        // `DragGesture.onChanged` de `CriterionRow`, muter `groups`
        // (@Published) pendant que SwiftUI traite encore la mise à jour de
        // vue en cours déclenche "Publishing changes from within view
        // updates is not allowed" — observé sur les réglettes Culture de
        // Big Mac, dont le `.onChange(of: state.groups)` redessine aussitôt
        // les départements pendant le même cycle.
        let clamped = max(0, min(5, value))
        DispatchQueue.main.async { [weak self] in
            self?.groups[groupIndex][rowIndex] = clamped
        }
    }

    public func toggleFavoriteDepartement(_ code: String) {
        if favoriteDepartementCodes.contains(code) { favoriteDepartementCodes.remove(code) } else { favoriteDepartementCodes.insert(code) }
    }

    /// Ajoute ou retire un favori en enregistrant l'inverse auprès de
    /// l'`UndoManager` de la fenêtre : Édition > Annuler / Rétablir.
    public func setFavorite(_ code: String, isOn: Bool, undoManager: UndoManager?) {
        if isOn { favoriteDepartementCodes.insert(code) } else { favoriteDepartementCodes.remove(code) }
        undoManager?.registerUndo(withTarget: self) { state in
            MainActor.assumeIsolated { state.setFavorite(code, isOn: !isOn, undoManager: undoManager) }
        }
        undoManager?.setActionName(isOn ? "Ajout aux favoris" : "Retrait des favoris")
    }

    public func setCountry(_ name: String) { country = name; query = name }
}
