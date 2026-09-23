import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Look-and-feel knobs mirroring the dc export's `$preview` props
/// (`accent`, `density`, `resultLayout`, `imagery`).
public final class ClassicTheme: ObservableObject {
    @Published public var accent: Color
    @Published public var compact: Bool
    @Published public var resultLayout: ResultLayout
    @Published public var showPhotos: Bool

    public enum ResultLayout: String, CaseIterable { case cards, list, rank }

    public init(
        accent: Color = .accentColor,
        compact: Bool = false,
        resultLayout: ResultLayout = .cards,
        showPhotos: Bool = true
    ) {
        self.accent = accent
        self.compact = compact
        self.resultLayout = resultLayout
        self.showPhotos = showPhotos
    }

    /// `color-mix(in oklab, accent 62%, white)` approximated by blending in sRGB.
    public var accentLight: Color { accent.mixed(with: .white, fraction: 0.62) }

    // Fixed palette (not user-configurable in the dc export).
    public static let background = Color(hex: 0xFFFFFF)
    public static let sidebarBg = Color(hex: 0xEFECE6)
    public static let border = Color(hex: 0xDDD8CE)
    public static let dividerLight = Color(hex: 0xF0ECE4)
    public static let cardAlt = Color(hex: 0xFAF9F6)
    public static let ink = Color(hex: 0x1C1B19)
    public static let inkPanel = Color(hex: 0xF4F2EE) // text on dark panels
    public static let body = Color(hex: 0x4A463F)
    public static let sub = Color(hex: 0x6F6A60)
    public static let faint = Color(hex: 0x8C867B)
    public static let faint2 = Color(hex: 0xA39D91)
    public static let darkPanel = Color(hex: 0x1C1B19)
    public static let darkPanelSub = Color(hex: 0xBDB7AB)
    public static let darkPanelFaint = Color(hex: 0xA39D91)
    public static let darkPanelDivider = Color(hex: 0x34312C)
    /// Étoile et sceau des favoris, partout dans l'app.
    public static let favorite = Color(hex: 0xFFD500)
    public static let track = Color(hex: 0xEAE6DE)
    public static let trackAlt = Color(hex: 0xC9C3B6)

    // Density-driven metrics.
    public var mainPadding: CGFloat { compact ? 24 : 40 }
    public var mainPaddingBottom: CGFloat { compact ? 40 : 56 }
    public var gap: CGFloat { compact ? 18 : 28 }
    public var cardPad: CGFloat { compact ? 15 : 22 }
    public var cardPadX: CGFloat { compact ? 16 : 20 }
    public var rowPad: CGFloat { compact ? 10 : 15 }
    public var rowPadTight: CGFloat { compact ? 8 : 12 }
    public var h1: CGFloat { compact ? 30 : 38 }
    public var h2: CGFloat { compact ? 25 : 32 }
}

public extension Color {
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

    private func resolveComponents() -> (Double, Double, Double) {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #elseif canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
        #else
        return (0, 0, 0)
        #endif
    }
}

public enum CFont {
    /// Archivo (display/body) — conservé pour compatibilité, non utilisé par
    /// les vues actives de l'app (toutes en SF Pro via `.rounded`/`.mono`) ;
    /// tombe sur le sans système si la police n'est pas embarquée.
    public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Archivo", size: size).weight(weight)
    }
    /// SF Pro Rounded (police système, design arrondi) — police de corps par
    /// défaut de toutes les vues actives de l'app.
    public static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// SF Mono (police système, design monospace) — pour libellés/valeurs
    /// numériques. Note : un ancien commentaire mentionnait "IBM Plex Mono",
    /// mais c'est bien la police monospace système qui est utilisée ici.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
