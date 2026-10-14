import SwiftUI
import AppKit

/// Look-and-feel constants mirroring the dc export's `$preview` props
/// (`accent`, `density`) — l'accent suit la couleur d'accent de l'app.
enum ClassicTheme {
    static let accent = Color.accentColor

    // Fixed palette (not user-configurable in the dc export).
    static let background = Color(hex: 0xFFFFFF)
    static let border = Color(hex: 0xDDD8CE)
    static let dividerLight = Color(hex: 0xF0ECE4)
    static let cardAlt = Color(hex: 0xFAF9F6)
    static let ink = Color(hex: 0x1C1B19)
    static let body = Color(hex: 0x4A463F)
    static let sub = Color(hex: 0x6F6A60)
    static let faint = Color(hex: 0x8C867B)
    static let faint2 = Color(hex: 0xA39D91)
    /// Étoile (cochée ou non), sceau des favoris et contour du département sélectionné : jaune doré, plus foncé que l'ancien
    /// #FFD500 sans virer au marron.
    static let favorite = Color(hex: 0xD9B000)
    static let track = Color(hex: 0xEAE6DE)

    // Density-driven metrics (densité normale).
    static let mainPadding: CGFloat = 40
    static let mainPaddingBottom: CGFloat = 56
    static let cardPadX: CGFloat = 20
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }

    /// Linear blend toward another color — a plain-sRGB stand-in for CSS's
    /// `color-mix(in oklab, ...)` (close enough for this palette).
    func mixed(with other: Color, fraction: Double) -> Color {
        let a = other.resolveComponents()
        let b = resolveComponents()
        let f = fraction
        return Color(
            red: b.0 * f + a.0 * (1 - f),
            green: b.1 * f + a.1 * (1 - f),
            blue: b.2 * f + a.2 * (1 - f)
        )
    }

    /// Teinte des tracés de départements sur les cartes : bleu éclairci en mode sombre.
    func mapTrace(dark: Bool) -> Color { dark ? mixed(with: .white, fraction: 0.6) : self }

    private func resolveComponents() -> (Double, Double, Double) {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}

enum CFont {
    /// SF Pro Rounded (police système, design arrondi) — police de corps par
    /// défaut de toutes les vues actives de l'app.
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// SF Mono (police système, design monospace) — pour libellés/valeurs
    /// numériques. Note : un ancien commentaire mentionnait "IBM Plex Mono",
    /// mais c'est bien la police monospace système qui est utilisée ici.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Palette adaptative clair/sombre des fenêtres de détail (Météo, Culture),
/// reprise par le Sélecteur et l'inspecteur.
struct DetailColors {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var window: Color { dark ? Color(hex: 0x1C1B19) : ClassicTheme.cardAlt }
    var card: Color { dark ? Color(hex: 0x262521) : .white }
    var ink: Color { dark ? Color(hex: 0xF4F2EE) : ClassicTheme.ink }
    var body: Color { dark ? Color(hex: 0xD9D4C9) : ClassicTheme.body }
    var sub: Color { dark ? Color(hex: 0xBDB7AB) : ClassicTheme.sub }
    var faint: Color { dark ? Color(hex: 0xA39D91) : ClassicTheme.faint }
    var faint2: Color { dark ? Color(hex: 0x8C867B) : ClassicTheme.faint2 }
    var border: Color { dark ? Color.white.opacity(0.15) : ClassicTheme.border }
    var divider: Color { dark ? Color.white.opacity(0.08) : ClassicTheme.dividerLight }
    var track: Color { dark ? Color.white.opacity(0.12) : ClassicTheme.track }
    /// Pastille du code département (inspecteur, carte des favoris).
    var badge: Color { dark ? Color.white.opacity(0.12) : ClassicTheme.border.opacity(0.5) }
}
