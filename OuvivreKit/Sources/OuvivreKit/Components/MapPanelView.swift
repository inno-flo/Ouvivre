import SwiftUI
import MapKit

/// The four plan types offered by the panel's type picker, mirroring Apple
/// Maps' own choices (Explorer / Conduite / Transports / Satellite).
public enum MapPlanType: String, CaseIterable, Identifiable {
    case explorer, voiture, transports, satellite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .explorer: "Explorer"
        case .voiture: "Voiture"
        case .transports: "Transports"
        case .satellite: "Satellite"
        }
    }

    public var icon: String {
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
        case .voiture: .standard(elevation: elevation, showsTraffic: true)
        case .transports: .standard(elevation: elevation, pointsOfInterest: .including([.publicTransport]))
        case .satellite: .hybrid(elevation: elevation)
        }
    }
}

/// A round map-type selector, styled to match MapKit's own native controls
/// (`MapCompass`, `MapPitchToggle`, `MapZoomStepper`) so it can sit in the
/// same `.mapControls` stack as them — MapKit has no built-in equivalent for
/// switching between named map styles (Explorer/Voiture/Transports/Satellite),
/// so this fills that one gap without introducing a different-looking control.
struct MapPlanTypeMenuButton: View {
    @Binding var planType: MapPlanType
    var icon: String = "globe.desk"
    var tint: Color = .black

    var body: some View {
        Menu {
            ForEach(MapPlanType.allCases) { type in
                Button { planType = type } label: { Label(type.label, systemImage: type.icon) }
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
        }
        .menuIndicator(.hidden)
        .modifier(RoundMapControlStyle())
        .frame(width: 32, height: 32)
        .help("Type de carte")
    }
}

/// Circular, solid-opaque chrome matching MapKit's own native control
/// buttons (e.g. `MapZoomStepper`) — translucent glass/material reads as
/// "no background" next to their solid look, so this uses a plain opaque
/// fill on every OS version instead of the (translucent-by-design) glass
/// button style.
private struct RoundMapControlStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .background(Color.white, in: Circle())
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

