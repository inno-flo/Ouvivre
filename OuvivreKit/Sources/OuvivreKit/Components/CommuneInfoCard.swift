import SwiftUI
import MapKit

/// Infobulle posée sur une étiquette de localité cliquée : commune, population,
/// densité et catégorie de taille.
struct CommuneTooltip {
    let info: CommuneInfo
    /// Position de l'étiquette cliquée, où l'infobulle est ancrée.
    let coordinate: CLLocationCoordinate2D

    /// Infobulle de la commune correspondant à `feature`, si c'est une
    /// localité (région, point d'intérêt et relief sont ignorés).
    init?(feature: MapFeature?) {
        guard let feature, feature.kind == .territory, let title = feature.title,
              let info = CommuneLookup.commune(named: title, near: feature.coordinate) else { return nil }
        self.info = info
        coordinate = feature.coordinate
    }
}

struct CommuneInfoCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }
    let info: CommuneInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(info.name)
                .font(CFont.rounded(13, weight: .bold))
                .foregroundStyle(c.ink)
            Text("\(frThousands(info.population)) habitants")
                .font(CFont.rounded(12, weight: .medium))
                .foregroundStyle(c.body)
            if let densite = info.densite {
                Text("\(frThousands(densite)) hab./km²")
                    .font(CFont.rounded(11))
                    .foregroundStyle(c.sub)
            }
            Text("\(info.category.rawValue) · \(FranceGeoData.nom(forCode: info.departementCode))")
                .font(CFont.rounded(11))
                .foregroundStyle(c.faint)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(c.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(c.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        // Au-dessus de l'étiquette, sans masquer le clic suivant sur la carte.
        .padding(.bottom, 14)
        .allowsHitTesting(false)
    }
}
