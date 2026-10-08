import SwiftUI
import CoreLocation

/// Alias de module : les types déclarés dans `@State` sont réécrits par la macro
/// dans un contexte où l'import local de CoreLocation n'est pas toujours visible.
typealias RecordPinCoordinate = CLLocationCoordinate2D

/// Emplacements des relevés de record de chaleur à repérer sur la carte du
/// département : écrits par la fenêtre Climat pour le mois sélectionné (un par année),
/// observé par la carte. Un objet partagé via l'environnement, car la carte et
/// le graphique sont deux frères dans la vue Département comme dans la fenêtre
/// Climat ; la carte l'observe directement (`PinnedMapCard`), sans repasser par
/// les vues parentes.
/// Un repère : emplacement du relevé et année(s) où le record du mois y a été
/// relevé (plusieurs si le même poste détient le record plusieurs années).
struct RecordPinMark: Identifiable {
    let coordinate: RecordPinCoordinate
    let years: [Int]
    var id: String { "\(coordinate.latitude),\(coordinate.longitude)" }
}

final class RecordPinModel: ObservableObject {
    /// Un repère par emplacement pour le mois sélectionné.
    @Published var marks: [RecordPinMark] = []
}

private struct RecordPinKey: EnvironmentKey {
    /// Instance de repli (jamais écrite ni lue utilement) pour les vues
    /// affichées hors d'un parent qui fournit le sien.
    static let defaultValue = RecordPinModel()
}

extension EnvironmentValues {
    var recordPin: RecordPinModel {
        get { self[RecordPinKey.self] }
        set { self[RecordPinKey.self] = newValue }
    }
}

/// Carte du département qui affiche le repère du record (soleil rouge) à
/// l'emplacement publié dans `RecordPinModel`.
struct PinnedMapCard: View {
    @ObservedObject var pin: RecordPinModel
    let names: [String]
    var focusCoordinate: CLLocationCoordinate2D?
    var focusTick = 0

    var body: some View {
        DepartementMapCard(
            names: names,
            focusCoordinate: focusCoordinate,
            focusTick: focusTick,
            pinMarks: pin.marks,
            fillsDepartement: false,
            resizable: true
        )
    }
}
