import SwiftUI
import MapKit

/// Cadre contenant une carte centrée sur un département (périmètre tracé,
/// ajusté pour occuper au mieux le cadre), avec deux boutons de type de
/// carte (Explorer / Satellite), deux boutons de zoom et un bouton de
/// recentrage. Partagé par les fenêtres de détail Météo et Culture.
public struct DepartementMapCard: View {
    let name: String
    let accent: Color

    @State private var mapType: MapPlanType = .explorer
    @State private var mapPosition: MapCameraPosition = .automatic
    /// Dernière région affichée, pour que les boutons de zoom partent de la
    /// vue courante (déplacement manuel compris).
    @State private var mapRegion: MKCoordinateRegion?

    public init(name: String, accent: Color) {
        self.name = name
        self.accent = accent
    }

    /// Rectangle englobant le périmètre du département, avec une petite
    /// marge — la carte s'y ajuste pour que le département occupe au mieux
    /// le cadre.
    private var departementRect: MKMapRect? {
        let points = (DepartementBoundaries.rings[name] ?? []).flatMap { $0 }.map { MKMapPoint($0) }
        guard let first = points.first else { return nil }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for pt in points.dropFirst() { rect = rect.union(MKMapRect(origin: pt, size: MKMapSize(width: 0, height: 0))) }
        return rect.insetBy(dx: -rect.width * 0.04, dy: -rect.height * 0.04)
    }

    private func zoomMap(by factor: Double) {
        guard let r = mapRegion else { return }
        let updated = MKCoordinateRegion(center: r.center, span: MKCoordinateSpan(
            latitudeDelta: min(170, max(0.002, r.span.latitudeDelta * factor)),
            longitudeDelta: min(360, max(0.002, r.span.longitudeDelta * factor))))
        withAnimation(.easeInOut(duration: 0.25)) { mapPosition = .region(updated) }
        mapRegion = updated
    }

    public var body: some View {
        let rings = DepartementBoundaries.rings[name] ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Spacer()
                ForEach([MapPlanType.explorer, MapPlanType.satellite]) { type in
                    Button { mapType = type } label: {
                        Text(type.label)
                            .font(CFont.sans(12, weight: .medium))
                            .foregroundStyle(mapType == type ? .white : ClassicTheme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(mapType == type ? ClassicTheme.ink : .clear)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(mapType == type ? ClassicTheme.ink : ClassicTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Button { zoomMap(by: 2) } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.plain).foregroundStyle(ClassicTheme.ink).help("Dézoomer")
                Button { zoomMap(by: 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.plain).foregroundStyle(ClassicTheme.ink).help("Zoomer")
                Button {
                    if let rect = departementRect { withAnimation(.easeInOut(duration: 0.25)) { mapPosition = .rect(rect) } }
                } label: { Image(systemName: "mappin.and.ellipse") }
                    .buttonStyle(.plain).foregroundStyle(ClassicTheme.ink).help("Recentrer sur le département")
            }
            if departementRect != nil {
                Map(position: $mapPosition) {
                    ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                        MapPolygon(coordinates: ring)
                            .foregroundStyle(accent.opacity(0.16))
                            .stroke(accent, lineWidth: 2)
                    }
                }
                .mapStyle(mapType.style(elevation: .automatic))
                .mapControls {}
                .onMapCameraChange { context in mapRegion = context.region }
                .onAppear { if let rect = departementRect { mapPosition = .rect(rect) } }
                .frame(height: 460)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Carte indisponible pour ce département.")
                    .font(CFont.sans(13)).foregroundStyle(ClassicTheme.faint)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }
}
