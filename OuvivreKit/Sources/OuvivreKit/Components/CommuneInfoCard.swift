import SwiftUI
import MapKit

/// Infobulle de population d'une commune, posée sur la localité cliquée.
struct CommuneTooltip {
    let info: CommuneInfo

    /// Demi-axes (points écran) de la zone de clic autour du nom d'une localité.
    private static let hitHalfWidth: CGFloat = 40
    private static let hitHalfHeight: CGFloat = 10

    /// Commune sous le point `point` (coordonnées locales de la carte), `nil`
    /// si le clic tombe hors de toute localité.
    init?(at point: CGPoint, proxy: MapProxy) {
        guard let center = proxy.convert(point, from: .local),
              let right = proxy.convert(CGPoint(x: point.x + Self.hitHalfWidth, y: point.y), from: .local),
              let below = proxy.convert(CGPoint(x: point.x, y: point.y + Self.hitHalfHeight), from: .local),
              let info = CommuneLookup.commune(
                near: center,
                halfWidth: abs(right.longitude - center.longitude),
                halfHeight: abs(below.latitude - center.latitude)) else { return nil }
        self.info = info
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
