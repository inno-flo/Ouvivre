import SwiftUI
import MapKit
#if os(macOS)
import AppKit
#endif

/// The four plan types offered by the panel's type picker, mirroring Apple
/// Maps' own choices (Explorer / Conduite / Transports / Satellite).
enum MapPlanType: String, CaseIterable, Identifiable {
    case explorer, voiture, transports, satellite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .explorer: "Explorer"
        case .voiture: "Voiture"
        case .transports: "Transports"
        case .satellite: "Satellite"
        }
    }

    var icon: String {
        switch self {
        case .explorer: "map"
        case .voiture: "car"
        case .transports: "tram"
        case .satellite: "globe.americas"
        }
    }

    func style(elevation: MapStyle.Elevation) -> MapStyle {
        switch self {
        case .explorer: .standard(elevation: elevation)
        case .voiture: .standard(elevation: elevation, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: true)
        case .transports: .standard(elevation: elevation, emphasis: .muted, pointsOfInterest: .including([.publicTransport, .airport]))
        case .satellite: .hybrid(elevation: elevation)
        }
    }
}

/// Bouton 3D/2D en surimposition (coin supérieur droit) affiché seulement en
/// vue Satellite : bascule le relief réaliste et l'inclinaison de la caméra.
/// Repasse en 2D dès qu'on quitte Satellite.
private struct SatelliteTiltButton: ViewModifier {
    let isSatellite: Bool
    @Binding var is3D: Bool
    @Binding var position: MapCameraPosition
    let camera: MapCamera?
    @State private var dragStartPitch: Double?

    private func setTilt(_ on: Bool) {
        is3D = on
        withAnimation(.easeInOut(duration: 0.5)) { applyPitch(on ? 60 : 0) }
    }

    private func applyPitch(_ pitch: Double) {
        guard let camera else { return }
        position = .camera(MapCamera(
            centerCoordinate: camera.centerCoordinate,
            distance: camera.distance,
            heading: camera.heading,
            pitch: pitch
        ))
    }

    /// Curseur vertical compact d'inclinaison, avec une puce noire comme dans
    /// Plans (haut = à plat, bas = très incliné). Le glissement est relatif et
    /// en phase avec la puce (elle suit exactement le pointeur) ; avec Option,
    /// le réglage est 5× plus fin (macOS). Calculé depuis l'angle du début du geste. La puce reflète l'angle réel de la caméra.
    private var pitchHandle: some View {
        let trackHeight: CGFloat = 90
        let pitch = min(80, max(0, camera?.pitch ?? 60))
        return ZStack(alignment: .top) {
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            Circle()
                .fill(.black)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .offset(y: 5 + (trackHeight - 24) * pitch / 80)
        }
        .frame(width: 20, height: trackHeight)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartPitch ?? (camera?.pitch ?? 60)
                    dragStartPitch = start
                    #if os(macOS)
                    let fine = NSEvent.modifierFlags.contains(.option)
                    #else
                    let fine = false
                    #endif
                    let degreesPerPoint = (80 / (trackHeight - 24)) * (fine ? 0.2 : 1)
                    applyPitch(min(80, max(0, start + value.translation.height * degreesPerPoint)))
                }
                .onEnded { _ in dragStartPitch = nil }
        )
        .help("Inclinaison · Option pour un réglage fin")
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isSatellite {
                    VStack(spacing: 8) {
                        Button { setTilt(!is3D) } label: {
                            Text(is3D ? "2D" : "3D")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                        .help(is3D ? "Passer en 2D" : "Passer en 3D")
                        if is3D { pitchHandle }
                    }
                    .padding(10)
                }
            }
            .onChange(of: isSatellite) { _, now in
                if !now && is3D { setTilt(false) }
            }
    }
}

extension View {
    func satelliteTiltButton(isSatellite: Bool, is3D: Binding<Bool>, position: Binding<MapCameraPosition>, camera: MapCamera?) -> some View {
        modifier(SatelliteTiltButton(isSatellite: isSatellite, is3D: is3D, position: position, camera: camera))
    }
}
