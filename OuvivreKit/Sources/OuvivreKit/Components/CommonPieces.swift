import SwiftUI

/// Small tracked-out uppercase caption used as an eyebrow/section marker.
struct Eyebrow: View {
    let text: String
    let color: Color
    let font: Font
    var tracking: CGFloat = 1.4

    init(_ text: String, color: Color, font: Font, tracking: CGFloat = 1.4) {
        self.text = text
        self.color = color
        self.font = font
        self.tracking = tracking
    }

    var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
    }
}
