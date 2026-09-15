import SwiftUI

/// One weighted-criterion row: label + tag on top, a draggable track with a
/// circular thumb below (0...5) — mirrors the dc export's slider rows used
/// on Géographie / Météo / Affiner.
public struct CriterionRow: View {
    @EnvironmentObject var theme: ClassicTheme
    let row: WeightedRow
    var thumbSize: CGFloat = 16
    var trackHeight: CGFloat = 4
    var labelFont: Font = CFont.sans(14, weight: .medium)
    let onChange: (Int) -> Void

    public init(row: WeightedRow, thumbSize: CGFloat = 16, trackHeight: CGFloat = 4, labelFont: Font = CFont.sans(14, weight: .medium), onChange: @escaping (Int) -> Void) {
        self.row = row
        self.thumbSize = thumbSize
        self.trackHeight = trackHeight
        self.labelFont = labelFont
        self.onChange = onChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label).font(labelFont).foregroundStyle(ClassicTheme.ink)
                Spacer()
                Text(row.tag)
                    .font(CFont.mono(11, weight: .medium))
                    .foregroundStyle(row.value >= 4 ? theme.accent : (row.value == 0 ? ClassicTheme.faint2 : ClassicTheme.faint))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ClassicTheme.track).frame(height: trackHeight)
                    Capsule().fill(theme.accent)
                        .frame(width: max(thumbSize / 2, geo.size.width * row.pct), height: trackHeight)
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(Circle().stroke(theme.accent, lineWidth: 2))
                        .offset(x: geo.size.width * row.pct - thumbSize / 2)
                }
                .frame(height: thumbSize)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let ratio = max(0, min(1, g.location.x / max(geo.size.width, 1)))
                            onChange(Int((ratio * 5).rounded()))
                        }
                )
            }
            .frame(height: thumbSize)
        }
    }
}
