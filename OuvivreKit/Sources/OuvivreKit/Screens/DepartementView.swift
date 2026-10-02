import SwiftUI

/// Vue d'un département favori (sidebar > Favoris) : en-tête, carte, puis les
/// contenus des fenêtres Culture et Météo réunis.
struct DepartementView: View {
    let departementCode: String
    @EnvironmentObject private var state: ClassicState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DepartementHeaderAndMap(departementCode: departementCode, state: state)
                CultureDetailView(departementCode: departementCode, embedded: true)
                MeteoDetailView(departementCode: departementCode, embedded: true)
            }
            .padding(24)
            .frame(maxWidth: 1340, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DetailColors(colorScheme).window)
    }
}
