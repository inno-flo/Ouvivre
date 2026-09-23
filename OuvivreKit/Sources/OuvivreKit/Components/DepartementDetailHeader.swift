import SwiftUI

/// En-tête commun aux fenêtres de détail d'un département (Météo, Culture) :
/// numéro, nom, chef-lieu, bouton de recentrage de la carte et étoile de
/// favoris, sur une seule ligne.
struct DepartementDetailHeader: View {
    let departementCode: String
    let name: String
    let accent: Color
    @ObservedObject var state: ClassicState
    let onRecenter: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(departementCode)
                    .font(CFont.rounded(20, weight: .bold))
                    .foregroundStyle(ClassicTheme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ClassicTheme.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                Text(name)
                    .font(CFont.rounded(20, weight: .bold))
                    .foregroundStyle(ClassicTheme.ink)
                if let chefLieu = FranceGeoData.chefsLieux[departementCode] {
                    Text(chefLieu)
                        .font(CFont.rounded(18))
                        .foregroundStyle(ClassicTheme.faint)
                    Button(action: onRecenter) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(CFont.rounded(13))
                            .foregroundStyle(ClassicTheme.faint)
                    }
                    .buttonStyle(.plain)
                    .help("Centrer la carte sur \(chefLieu)")
                }
            }
            Spacer(minLength: 8)
            let isFavorite = state.favoriteDepartementCodes.contains(departementCode)
            Button {
                state.toggleFavoriteDepartement(departementCode)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(isFavorite ? ClassicTheme.favorite : ClassicTheme.faint)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
        }
    }
}

extension View {
    /// Fond crème et taille minimale communes aux fenêtres de détail.
    func departementDetailWindow() -> some View {
        background(ClassicTheme.background)
            .frame(minWidth: 760, minHeight: 640)
    }
}
