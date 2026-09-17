import SwiftUI

/// Étape 04 — Affiner: 4 criteria groups (Culture/Taille/Mobilité/Qualité
/// de vie) + a live-reordering final ranking and livability sources.
public struct AffinerView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("ÉTAPE 02 — CULTURE · TAILLE · MOBILITÉ", color: theme.accent).padding(.bottom, 16)
            Text("Trois familles de critères et les classements de livabilité. Le podium de droite se réordonne en direct.")
                .font(CFont.sans(15))
                .foregroundStyle(ClassicTheme.sub)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.bottom, 24)

            AdaptiveTwoColumn(leftWeight: 1.35, rightWeight: 0.65, gap: theme.gap) {
                groupsGrid
            } right: {
                VStack(spacing: 14) {
                    rankingCard
                    sourcesCard
                }
            }
        }
    }

    private var groupsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 252), spacing: 16)], spacing: 16) {
            ForEach(derived.groups) { g in
                Card(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Eyebrow(g.title, color: ClassicTheme.faint)
                            Spacer()
                            Text("\(g.count) CRITÈRES").font(CFont.mono(10)).foregroundStyle(ClassicTheme.faint2)
                        }
                        .padding(.horizontal, theme.cardPadX).padding(.top, 16).padding(.bottom, 12)

                        ForEach(g.rows) { row in
                            CriterionRow(row: row, thumbSize: 11, trackHeight: 3, labelFont: CFont.sans(13)) { state.setGroup(g.id, row.id, value: $0) }
                                .padding(.horizontal, theme.cardPadX).padding(.vertical, 8)
                        }
                        Spacer(minLength: 4)
                    }
                }
            }
        }
    }

    private var rankingCard: some View {
        Card(padding: theme.cardPadX) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("CLASSEMENT FINAL", color: ClassicTheme.faint).padding(.bottom, 12)
                ForEach(derived.cities) { c in
                    Button { state.go(.ville) } label: {
                        HStack(spacing: 10) {
                            Text(c.rank).font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.faint2).frame(width: 16, alignment: .leading)
                            Text(c.name).font(CFont.sans(14, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                            Spacer()
                            Text("\(c.score)").font(CFont.mono(13, weight: .medium)).foregroundStyle(theme.accent)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                }
                AccentButton("Comparer les 3 premières →", fill: theme.accent) { state.go(.compare) }
                    .padding(.top, 14)
            }
        }
    }

    private var sourcesCard: some View {
        Card(padding: theme.cardPadX, background: ClassicTheme.sidebarBg) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("LIVABILITÉ — SOURCES", color: ClassicTheme.faint).padding(.bottom, 10)
                ForEach(ClassicStatic.rankings) { r in
                    HStack {
                        Text(r.key).font(CFont.sans(12)).foregroundStyle(ClassicTheme.body)
                        Spacer()
                        Text(r.value).font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}
