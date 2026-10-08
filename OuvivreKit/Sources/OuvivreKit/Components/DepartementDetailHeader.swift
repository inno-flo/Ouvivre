import SwiftUI

/// En-tête commun aux fenêtres de détail d'un département (Météo, Culture) :
/// numéro, nom, chef-lieu, bouton de recentrage de la carte et, à sa droite,
/// étoile de favoris, sur une seule ligne.
struct DepartementDetailHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }
    let departementCode: String
    @ObservedObject var state: ClassicState
    let onRecenter: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(departementCode)
                    .font(CFont.rounded(20, weight: .bold))
                    .foregroundStyle(c.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(c.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                Text(FranceGeoData.nom(forCode: departementCode))
                    .font(CFont.rounded(20, weight: .bold))
                    .foregroundStyle(c.ink)
                if let chefLieu = FranceGeoData.chefsLieux[departementCode] {
                    Text(chefLieu)
                        .font(CFont.rounded(18))
                        .foregroundStyle(c.faint)
                    Button(action: onRecenter) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 13))
                            .frame(width: 16, height: 16)
                            .foregroundStyle(c.faint)
                    }
                    .buttonStyle(.plain)
                    .help("Centrer la carte sur \(chefLieu)")
                }
                // Étoile de favoris, à droite de l'icône de recentrage.
                let isFavorite = state.favoriteDepartementCodes.contains(departementCode)
                Button {
                    state.toggleFavoriteDepartement(departementCode)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(isFavorite ? ClassicTheme.favorite : c.faint)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
            }
            Spacer(minLength: 8)
        }
    }
}

/// En-tête puis carte du département, communs aux fenêtres de détail
/// (Météo, Culture) et à la vue Département : le bouton de recentrage de
/// l'en-tête centre la carte sur le chef-lieu.
struct DepartementHeaderAndMap: View {
    let departementCode: String
    @ObservedObject var state: ClassicState
    @State private var mapFocusTick = 0
    @Environment(\.recordPin) private var recordPin

    var body: some View {
        DepartementDetailHeader(departementCode: departementCode, state: state) { mapFocusTick += 1 }
        PinnedMapCard(
            pin: recordPin,
            names: [FranceGeoData.nom(forCode: departementCode)],
            focusCoordinate: FranceGeoData.chefsLieuxCoordinates[departementCode],
            focusTick: mapFocusTick
        )
    }
}

/// Enveloppe dans un `ScrollView` seulement quand `enabled`.
struct OptionalScroll<Content: View>: View {
    let enabled: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if enabled { ScrollView { content } } else { content }
    }
}

extension View {
    /// Fond #FAF9F6 et taille minimale communes aux fenêtres de détail —
    /// sans effet en mode intégré (vue Département).
    @ViewBuilder
    func departementDetailWindow(_ enabled: Bool) -> some View {
        if enabled { modifier(DetailWindowStyle()) } else { self }
    }
}

private struct DetailWindowStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .background(DetailColors(colorScheme).window)
            .frame(minWidth: 760, minHeight: 640)
    }
}
