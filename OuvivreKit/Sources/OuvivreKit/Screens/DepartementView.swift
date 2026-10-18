import SwiftUI
import CoreLocation

/// Vue d'un département favori (sidebar > Favoris) : en-tête, carte, puis les
/// contenus des fenêtres Climat et Culture réunis, dans cet ordre.
struct DepartementView: View {
    let departementCode: String
    @EnvironmentObject private var state: ClassicState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var recordPin = RecordPinModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DepartementHeaderAndMap(departementCode: departementCode, state: state, showsFlag: true)
                MeteoDetailView(departementCode: departementCode, embedded: true)
                // Une ligne vide sépare la rubrique Culture de la fin du Climat.
                CultureDetailView(departementCode: departementCode, embedded: true)
                    .padding(.top, 22)
            }
            .environment(\.recordPin, recordPin)
            .padding(24)
            .frame(maxWidth: 1340, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DetailColors(colorScheme).window)
    }
}

/// Fenêtre séparée d'un département favori (double-clic dans la sidebar) :
/// la vue Département avec son propre état (favoris
/// synchronisés avec la fenêtre principale via `UserDefaults`).
public struct DepartementWindowView: View {
    /// Identifiant de la scène `WindowGroup(for: String.self)` déclarée par
    /// l'app — la valeur passée à `openWindow` est le code du département.
    public static let windowID = "departement-detail"

    let departementCode: String
    @StateObject private var state = ClassicState()

    public init(departementCode: String) { self.departementCode = departementCode }

    public var body: some View {
        DepartementView(departementCode: departementCode)
            .departementDetailWindow(true)
            .environmentObject(state)
    }
}
