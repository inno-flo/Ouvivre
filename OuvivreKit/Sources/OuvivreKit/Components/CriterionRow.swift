import SwiftUI

/// A single weighted-criterion row (0...2), shared by the proximity and
/// Culture sliders — mirrors the dc export's `row()` helper.
struct WeightedRow: Identifiable {
    let id: Int
    let label: String
    let value: Int
    var maxValue: Int { ClassicState.maxWeight }

    /// Libellé du niveau, majuscule initiale ("Important").
    var tag: String {
        let raw = ClassicStatic.tags[min(value, ClassicStatic.tags.count - 1)]
        return raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
    }
    var pct: CGFloat { CGFloat(value) / CGFloat(maxValue) }
}

/// One weighted-criterion row: label + tag on top, a draggable track with a
/// circular thumb below (0...2) — mirrors the dc export's slider rows,
/// with the criterion's SF Symbol (`ClassicStatic.criterionIcons`, shared
/// with the Favoris table) before the label.
struct CriterionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let row: WeightedRow
    var thumbSize: CGFloat = 16
    let onChange: (Int) -> Void

    private let trackHeight: CGFloat = 4
    /// Facteur de croissance de chaque puce par rapport à la précédente
    /// (1,5 = +50 % : "important" 50 % plus grosse qu'"indifférent",
    /// "déterminant" 50 % plus grosse qu'"important").
    private let dotGrowthPerStep: CGFloat = 1.5

    var body: some View {
        let c = DetailColors(colorScheme)
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let icon = ClassicStatic.criterionIcons[row.label] {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(ClassicTheme.accent)
                        .frame(width: 18, alignment: .leading)
                }
                Text("\(row.label) :").font(CFont.rounded(13, weight: .medium)).foregroundStyle(c.body)
                Text(row.tag)
                    .font(CFont.rounded(10, weight: .medium))
                    .foregroundStyle(row.value > 0 ? ClassicTheme.accent : c.faint)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                // La piste utile est réduite de `thumbSize` de chaque côté
                // pour que le centre du curseur reste toujours entre
                // `thumbSize/2` et `trackWidth - thumbSize/2` — sinon, aux
                // valeurs extrêmes (0 ou max), le curseur déborde du cadre.
                let trackWidth = max(0, geo.size.width - thumbSize)
                let thumbCenterX = thumbSize / 2 + trackWidth * row.pct
                ZStack(alignment: .leading) {
                    Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.2) : ClassicTheme.track).frame(height: trackHeight)
                        .padding(.horizontal, thumbSize / 2)
                    Capsule().fill(ClassicTheme.accent)
                        .frame(width: max(thumbSize / 2, thumbCenterX), height: trackHeight)
                    ForEach(0...row.maxValue, id: \.self) { step in
                        let stepX = thumbSize / 2 + trackWidth * CGFloat(step) / CGFloat(row.maxValue)
                        // Chaque puce grossit de `dotGrowthPerStep` par
                        // rapport à la précédente (la 1ʳᵉ garde la taille de
                        // base 4pt).
                        let dotSize = 4 * pow(dotGrowthPerStep, CGFloat(step))
                        Circle()
                            .fill(step <= row.value ? Color.white.opacity(0.9) : (colorScheme == .dark ? Color.white.opacity(0.4) : ClassicTheme.faint2))
                            .frame(width: dotSize, height: dotSize)
                            .offset(x: stepX - dotSize / 2)
                    }
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(Circle().stroke(ClassicTheme.accent, lineWidth: 2))
                        .offset(x: thumbCenterX - thumbSize / 2)
                }
                .frame(height: thumbSize)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let ratio = max(0, min(1, (g.location.x - thumbSize / 2) / max(trackWidth, 1)))
                            onChange(Int((ratio * CGFloat(row.maxValue)).rounded()))
                        }
                )
            }
            .frame(height: thumbSize)
        }
    }
}
