import SwiftUI

/// One weighted-criterion row: label + tag on top, a draggable track with a
/// circular thumb below (0...5) — mirrors the dc export's slider rows used
/// on Géographie / Météo / Affiner.
public struct CriterionRow: View {
    @EnvironmentObject var theme: ClassicTheme
    @Environment(\.colorScheme) private var colorScheme
    let row: WeightedRow
    var thumbSize: CGFloat = 16
    var trackHeight: CGFloat = 4
    var labelFont: Font = CFont.rounded(14, weight: .medium)
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
    /// Override for the tag's default font — every active call site passes
    /// an explicit `CFont.rounded(...)` (SF Pro Rounded).
    var tagFont: Font?
    /// Casse du tag : `.upper` par défaut (`WeightedRow.tag`), ou minuscules /
    /// majuscule initiale à partir du libellé brut.
    public enum TagCase { case upper, lower, capitalized }
    var tagCase: TagCase = .upper
    /// SF Symbol affiché devant le libellé — `ClassicStatic.criterionIcons`
    /// pour reprendre celui du tableau Favoris. Absent par défaut : les
    /// réglettes sans icône (Météo, Affiner) gardent leur mise en page.
    var icon: String?
    let onChange: (Int) -> Void

    public init(row: WeightedRow, thumbSize: CGFloat = 16, trackHeight: CGFloat = 4, labelFont: Font = CFont.rounded(14, weight: .medium), labelColor: Color = ClassicTheme.ink, extraDotScaleFromSecond: CGFloat = 1.0, dotGrowthPerStep: CGFloat = 1.25, tagFont: Font? = nil, tagCase: TagCase = .upper, icon: String? = nil, onChange: @escaping (Int) -> Void) {
        self.row = row
        self.thumbSize = thumbSize
        self.trackHeight = trackHeight
        self.labelFont = labelFont
        self.labelColor = labelColor
        self.extraDotScaleFromSecond = extraDotScaleFromSecond
        self.dotGrowthPerStep = dotGrowthPerStep
        self.tagFont = tagFont
        self.tagCase = tagCase
        self.icon = icon
        self.onChange = onChange
    }

    private var tagText: String {
        let raw = row.tags[min(row.value, row.tags.count - 1)]
        switch tagCase {
        case .upper: return row.tag
        case .lower: return raw.lowercased()
        case .capitalized: return raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accent)
                        .frame(width: 18, alignment: .leading)
                }
                Text("\(row.label) :").font(labelFont).foregroundStyle(labelColor)
                Text(tagText)
                    .font(tagFont ?? CFont.mono(11, weight: .medium))
                    .foregroundStyle(row.value >= row.maxValue - 1 ? theme.accent : (row.value == 0 ? (colorScheme == .dark ? Color(hex: 0xA39D91) : ClassicTheme.faint) : (colorScheme == .dark ? Color(hex: 0xD9D4C9) : ClassicTheme.body)))
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
                            .fill(step <= row.value ? Color.white.opacity(0.9) : (colorScheme == .dark ? Color.white.opacity(0.4) : ClassicTheme.faint2))
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
