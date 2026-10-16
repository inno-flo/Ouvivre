import SwiftUI
import MapKit

/// Infobulle de population d'une commune, posée sur la localité cliquée.
struct CommuneTooltip {
    let info: CommuneInfo

    /// Demi-axes (points écran) de la zone de clic autour du nom d'une localité.
    static let hitHalfWidth: CGFloat = 45
    static let hitHalfHeight: CGFloat = 14

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
            Text(info.category.rawValue)
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

/// Région affichée, mise à jour en continu par la carte : seule l'infobulle la
/// lit, si bien que la suivre ne réévalue pas toute la vue parente.
@Observable
final class MapCameraTracker {
    var region: MKCoordinateRegion?
}

/// Pose l'infobulle au-dessus de la commune, en surimpression de la carte plutôt
/// que comme `Annotation` : MapKit masque les annotations qui entrent en collision
/// avec ses étiquettes, ce qui faisait disparaître l'infobulle d'une localité à
/// l'autre. La position suit la caméra (`camera`) pendant les déplacements.
struct CommuneTooltipOverlay: View {
    let tooltip: CommuneTooltip?
    let proxy: MapProxy
    let camera: MapCameraTracker

    var body: some View {
        let _ = camera.region
        if let tooltip, let point = proxy.convert(tooltip.info.coordinate, to: .local) {
            // Vue de taille nulle posée sur la commune : la carte, alignée par
            // son bord bas, se centre au-dessus du point.
            Color.clear
                .frame(width: 0, height: 0)
                .overlay(alignment: .bottom) { CommuneInfoCard(info: tooltip.info).fixedSize() }
                .position(point)
        }
    }
}

/// Mise au point : zone sensible au clic de chaque commune visible, en violet à
/// 50 %, avec son centre marqué d'un point — pour vérifier si elle est décalée
/// du nom dessiné par MapKit. Un clic retient une commune quand son centre
/// tombe dans l'ellipse de `CommuneTooltip.hitHalfWidth` × `hitHalfHeight`
/// autour du clic, c'est-à-dire quand le clic tombe dans la même ellipse
/// autour de son centre : c'est celle-ci qui est dessinée. Rien n'est dessiné
/// au-delà de `maxCount` communes visibles (carte très dézoomée).
struct CommuneHitZonesOverlay: View {
    /// Passer à `false` pour masquer les zones une fois le réglage terminé.
    static let isEnabled = true
    private static let maxCount = 3_000

    let proxy: MapProxy
    let camera: MapCameraTracker

    var body: some View {
        if Self.isEnabled, let region = camera.region {
            let latitudes = (region.center.latitude - region.span.latitudeDelta * 0.6)...(region.center.latitude + region.span.latitudeDelta * 0.6)
            let longitudes = (region.center.longitude - region.span.longitudeDelta * 0.6)...(region.center.longitude + region.span.longitudeDelta * 0.6)
            let communes = CommuneLookup.communes(latitudes: latitudes, longitudes: longitudes)
            // Points écran calculés ici (acteur principal), pas dans le `Canvas`.
            let points = communes.count <= Self.maxCount ? communes.compactMap { proxy.convert($0.coordinate, to: .local) } : []
            Canvas { context, _ in
                let hw = CommuneTooltip.hitHalfWidth, hh = CommuneTooltip.hitHalfHeight
                for p in points {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - hw, y: p.y - hh, width: hw * 2, height: hh * 2)), with: .color(.purple.opacity(0.5)))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(.purple))
                }
            }
            .allowsHitTesting(false)
        }
    }
}
