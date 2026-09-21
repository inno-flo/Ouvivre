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
    var labelColor: Color = ClassicTheme.ink
    /// Multiplicateur supplémentaire appliqué à toutes les puces sauf la
    /// première (dont la taille de base reste inchangée) — utilisé par les
    /// réglettes de proximité, qui veulent des puces 2, 3, 4... 10 % plus
    /// grosses que le reste des réglettes de l'app.
    var extraDotScaleFromSecond: CGFloat = 1.0
    /// Facteur de croissance de chaque puce par rapport à la précédente
    /// (1,25 par défaut = +25 % ; "Géographie et Culture" de Big Mac passe
    /// 1,5 = +50 % : "important" 50 % plus grosse qu'"indifférent",
    /// "déterminant" 50 % plus grosse qu'"important").
    var dotGrowthPerStep: CGFloat = 1.25
    /// Override for the tag's default IBM Plex Mono font — e.g. Big Mac SF
    /// swaps in SF Pro Medium here without touching every other caller.
    var tagFont: Font?
    /// Affiche le tag avec une majuscule initiale ("Indifférent").
    var capitalizeTag = false
    let onChange: (Int) -> Void

    public init(row: WeightedRow, thumbSize: CGFloat = 16, trackHeight: CGFloat = 4, labelFont: Font = CFont.sans(14, weight: .medium), labelColor: Color = ClassicTheme.ink, extraDotScaleFromSecond: CGFloat = 1.0, dotGrowthPerStep: CGFloat = 1.25, tagFont: Font? = nil, capitalizeTag: Bool = false, onChange: @escaping (Int) -> Void) {
        self.row = row
        self.thumbSize = thumbSize
        self.trackHeight = trackHeight
        self.labelFont = labelFont
        self.labelColor = labelColor
        self.extraDotScaleFromSecond = extraDotScaleFromSecond
        self.dotGrowthPerStep = dotGrowthPerStep
        self.tagFont = tagFont
        self.capitalizeTag = capitalizeTag
        self.onChange = onChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label).font(labelFont).foregroundStyle(labelColor)
                Spacer()
                Text(capitalizeTag ? row.tag.prefix(1).uppercased() + row.tag.dropFirst() : row.tag)
                    .font(tagFont ?? CFont.mono(11, weight: .medium))
                    .foregroundStyle(row.value >= row.maxValue - 1 ? theme.accent : (row.value == 0 ? ClassicTheme.faint2 : ClassicTheme.faint))
            }
            GeometryReader { geo in
                // La piste utile est réduite de `thumbSize` de chaque côté
                // pour que le centre du curseur reste toujours entre
                // `thumbSize/2` et `trackWidth - thumbSize/2` — sinon, aux
                // valeurs extrêmes (0 ou max), le curseur déborde du cadre.
                let trackWidth = max(0, geo.size.width - thumbSize)
                let thumbCenterX = thumbSize / 2 + trackWidth * row.pct
                ZStack(alignment: .leading) {
                    Capsule().fill(ClassicTheme.track).frame(height: trackHeight)
                        .padding(.horizontal, thumbSize / 2)
                    Capsule().fill(theme.accent)
                        .frame(width: max(thumbSize / 2, thumbCenterX), height: trackHeight)
                    ForEach(0...row.maxValue, id: \.self) { step in
                        let stepX = thumbSize / 2 + trackWidth * CGFloat(step) / CGFloat(row.maxValue)
                        // Chaque puce est 25 % plus grosse que la précédente
                        // (la 1ʳᵉ garde la taille de base 4pt) ; au-delà de la
                        // 1ʳᵉ, `extraDotScaleFromSecond` applique un facteur
                        // supplémentaire (réglettes de proximité : +10 %).
                        let dotSize = 4 * pow(dotGrowthPerStep, CGFloat(step)) * (step > 0 ? extraDotScaleFromSecond : 1)
                        Circle()
                            .fill(step <= row.value ? Color.white.opacity(0.9) : ClassicTheme.faint2)
                            .frame(width: dotSize, height: dotSize)
                            .offset(x: stepX - dotSize / 2)
                    }
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(Circle().stroke(theme.accent, lineWidth: 2))
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
