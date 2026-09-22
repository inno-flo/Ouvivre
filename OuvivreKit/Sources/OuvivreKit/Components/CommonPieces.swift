import SwiftUI

/// Small tracked-out uppercase caption used as an eyebrow/section marker.
public struct Eyebrow: View {
    let text: String
    var color: Color
    var size: CGFloat = 10
    /// Override for the default font — every active call site now passes
    /// an explicit `CFont.rounded(...)`, but the default below matches that
    /// same convention (SF Pro Rounded) rather than the old monospaced one.
    var font: Font?
    var tracking: CGFloat = 1.4

    public init(_ text: String, color: Color, size: CGFloat = 10, font: Font? = nil, tracking: CGFloat = 1.4) {
        self.text = text
        self.color = color
        self.size = size
        self.font = font
        self.tracking = tracking
    }

    public var body: some View {
        Text(text)
            .font(font ?? CFont.rounded(size, weight: .medium))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

/// A plain white bordered card, the base container reused across every screen.
public struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var background: Color = .white
    @ViewBuilder var content: Content

    public init(padding: CGFloat = 18, background: Color = .white, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.background = background
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }
}

/// Solid accent-colored call-to-action pill (e.g. "Comparer →").
public struct AccentButton: View {
    let title: String
    var foreground: Color = .white
    var fill: Color
    let action: () -> Void

    public init(_ title: String, fill: Color, foreground: Color = .white, action: @escaping () -> Void) {
        self.title = title
        self.fill = fill
        self.foreground = foreground
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(CFont.sans(13.5, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

/// Outlined secondary button (e.g. "Réinitialiser", "Sauvegarder").
public struct OutlineButton: View {
    let title: String
    var color: Color = ClassicTheme.faint
    var border: Color = ClassicTheme.border
    let action: () -> Void

    public init(_ title: String, color: Color = ClassicTheme.faint, border: Color = ClassicTheme.border, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.border = border
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(CFont.mono(11, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A thin rounded progress bar (used for family/region/bar-chart scores).
public struct MiniBar: View {
    let pct: CGFloat
    let fill: Color
    var track: Color = ClassicTheme.track
    var height: CGFloat = 4

    public init(pct: CGFloat, fill: Color, track: Color = ClassicTheme.track, height: CGFloat = 4) {
        self.pct = pct
        self.fill = fill
        self.track = track
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(0, geo.size.width * min(1, max(0, pct))))
            }
        }
        .frame(height: height)
    }
}

/// Diagonal-stripe placeholder used everywhere a real photo would go.
public struct PhotoPlaceholder: View {
    var label: String? = nil
    var height: CGFloat = 196

    public init(label: String? = nil, height: CGFloat = 196) {
        self.label = label
        self.height = height
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            StripePattern()
            if let label {
                Text(label)
                    .font(CFont.mono(10))
                    .foregroundStyle(ClassicTheme.faint)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(ClassicTheme.background)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(ClassicTheme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(14)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

private struct StripePattern: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 12.7 // ~9px diagonal repeat, matches the 135deg 9px CSS stripes
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF2EFE9)))
            var x: CGFloat = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + step / 2, y: 0))
                path.addLine(to: CGPoint(x: x + step / 2, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(Color(hex: 0xE9E5DC)))
                x += step * 2
            }
        }
    }
}
