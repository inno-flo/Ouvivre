import SwiftUI

/// Vue d'un département favori (sidebar > Favoris) : en-tête, carte, puis les
/// contenus des fenêtres Culture et Météo réunis.
public struct DepartementView: View {
    let departementCode: String
    @EnvironmentObject private var theme: ClassicTheme
    @EnvironmentObject private var state: ClassicState
    @State private var mapFocusTick = 0

    public init(departementCode: String) { self.departementCode = departementCode }

    private var name: String {
        FranceGeoData.departements.first { $0.codeInsee == departementCode }?.nom ?? departementCode
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DepartementDetailHeader(departementCode: departementCode, name: name, accent: theme.accent, state: state) { mapFocusTick += 1 }
                DepartementMapCard(name: name, accent: theme.accent, focusCoordinate: FranceGeoData.chefsLieuxCoordinates[departementCode], focusTick: mapFocusTick, roundedFont: true)
                CultureDetailView(departementCode: departementCode, embedded: true)
                MeteoDetailView(departementCode: departementCode, embedded: true)
            }
            .padding(24)
            .frame(maxWidth: 1340, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
