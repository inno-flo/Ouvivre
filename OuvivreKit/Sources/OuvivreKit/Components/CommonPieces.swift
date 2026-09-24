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
