import SwiftUI

/// Comparateur — side-by-side table of the top 3 cities, criterion by
/// criterion, with the best cell per row highlighted.
public struct CompareView: View {
    @EnvironmentObject var theme: ClassicTheme
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    private let labelColW: CGFloat = 200

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("COMPARATEUR", color: theme.accent).padding(.bottom, 12)
            Text("Trois villes, critère par critère")
                .font(CFont.sans(theme.h2, weight: .semibold))
                .foregroundStyle(ClassicTheme.ink)
                .padding(.bottom, 8)
            Text("La meilleure valeur de chaque ligne est mise en avant. Les écarts inférieurs à 3 points sont considérés comme équivalents.")
                .font(CFont.sans(15))
                .foregroundStyle(ClassicTheme.sub)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.bottom, 24)

            ScrollView(.horizontal, showsIndicators: true) {
                table.frame(minWidth: 700)
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("CRITÈRE").font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.faint)
                    .frame(width: labelColW, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 14)
                ForEach(Array(derived.compareHeads.enumerated()), id: \.offset) { _, h in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.name).font(CFont.sans(16, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                        Text(h.sub).font(CFont.mono(10)).foregroundStyle(ClassicTheme.faint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .overlay(Rectangle().fill(ClassicTheme.border).frame(width: 1), alignment: .leading)
                }
            }
            .background(ClassicTheme.sidebarBg)
            .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.border).frame(height: 1) }

            ForEach(derived.compareRows) { row in
                HStack(spacing: 0) {
                    Text(row.label).font(CFont.sans(13, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                        .frame(width: labelColW, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        .background(ClassicTheme.cardAlt)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, c in
                        HStack(spacing: 8) {
                            Text(c.value)
                                .font(CFont.sans(13, weight: c.best ? .semibold : .regular))
                                .foregroundStyle(c.best ? ClassicTheme.ink : ClassicTheme.sub)
                            if c.best {
                                Text("MEILLEUR")
                                    .font(CFont.mono(9, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        .overlay(Rectangle().fill(ClassicTheme.dividerLight).frame(width: 1), alignment: .leading)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
            }

            HStack(spacing: 0) {
                Text("SCORE OUVIVRE").font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.darkPanelFaint)
                    .frame(width: labelColW, alignment: .leading).padding(.horizontal, 18)
                ForEach(derived.compareScores, id: \.self) { score in
                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Text("\(score)").font(CFont.mono(26, weight: .medium)).foregroundStyle(theme.accentLight)
                        Text("/100").font(CFont.mono(10)).foregroundStyle(ClassicTheme.darkPanelFaint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .overlay(Rectangle().fill(ClassicTheme.darkPanelDivider).frame(width: 1), alignment: .leading)
                }
            }
            .background(ClassicTheme.darkPanel)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
    }
}
