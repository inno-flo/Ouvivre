import SwiftUI

/// Étape 03 — Météo: 9 weighted criteria + the 5 resulting cities, shown in
/// one of three layouts (cards / list / rank) controlled by `theme.resultLayout`.
public struct MeteoView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("ÉTAPE 04 — CLIMAT · SAVOIE / HAUTE‑SAVOIE", color: theme.accent).padding(.bottom, 12)
            Text("Le climat que vous supportez")
                .font(CFont.sans(theme.h2, weight: .semibold))
                .foregroundStyle(ClassicTheme.ink)
                .padding(.bottom, 8)
            Text("Normales 1991‑2020 et indices de confort. Les cinq villes sont recalculées en direct, géographie incluse.")
                .font(CFont.sans(15))
                .foregroundStyle(ClassicTheme.sub)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.bottom, 24)

            AdaptiveTwoColumn(leftWeight: 0.8, rightWeight: 1.2, gap: theme.gap) {
                slidersCard
            } right: {
                resultsColumn
            }
        }
    }

    private var slidersCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(derived.meteoRows) { row in
                    CriterionRow(row: row, thumbSize: 14, labelFont: CFont.sans(13, weight: .medium)) { state.setMeteo(row.id, value: $0) }
                        .padding(.horizontal, theme.cardPadX).padding(.vertical, theme.rowPadTight)
                        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var resultsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("RÉSULTAT — 5 VILLES SUR 8 ANALYSÉES", color: ClassicTheme.faint)
                Spacer()
                Button { state.go(.affiner) } label: {
                    Text("AFFINER LE CHOIX →").font(CFont.mono(11, weight: .medium)).foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            switch theme.resultLayout {
            case .cards: cardsLayout
            case .list: listLayout
            case .rank: rankLayout
            }
        }
    }

    private var cardsLayout: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 228), spacing: 16)], spacing: 16) {
            ForEach(derived.cities) { c in
                Button { state.go(.ville) } label: {
                    VStack(spacing: 0) {
                        if theme.showPhotos { PhotoPlaceholder(label: "photo \(c.name)", height: 120) }
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(c.name).font(CFont.sans(17, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                                Spacer()
                                Text("\(c.score)").font(CFont.mono(15, weight: .medium)).foregroundStyle(theme.accent)
                            }
                            Text(c.sub).font(CFont.sans(12)).foregroundStyle(ClassicTheme.faint).padding(.vertical, 5)
                            VStack(spacing: 7) {
                                ForEach(c.bars, id: \.key) { b in
                                    HStack(spacing: 8) {
                                        Text(b.key).font(CFont.mono(9)).foregroundStyle(ClassicTheme.faint2).frame(width: 42, alignment: .leading)
                                        MiniBar(pct: b.pct, fill: theme.accent, height: 3)
                                        Text("\(b.v)").font(CFont.mono(10)).foregroundStyle(ClassicTheme.sub).frame(width: 34, alignment: .trailing)
                                    }
                                }
                            }
                            .padding(.top, 5)
                        }
                        .padding(.horizontal, 15).padding(.top, 14).padding(.bottom, 16)
                    }
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var listLayout: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(derived.cities) { c in
                    Button { state.go(.ville) } label: {
                        HStack(spacing: 16) {
                            Text(c.rank).font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.faint2).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(CFont.sans(15, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                                Text(c.sub).font(CFont.sans(12)).foregroundStyle(ClassicTheme.faint)
                            }
                            Spacer()
                            Text(c.inline).font(CFont.mono(11)).foregroundStyle(ClassicTheme.sub).multilineTextAlignment(.trailing)
                            Text("\(c.score)").font(CFont.mono(16, weight: .medium)).foregroundStyle(theme.accent).frame(width: 38, alignment: .trailing)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var rankLayout: some View {
        Card(padding: 18) {
            VStack(spacing: 0) {
                ForEach(derived.cities) { c in
                    Button { state.go(.ville) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(c.rank).font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.faint2)
                                Text(c.name).font(CFont.sans(16, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                                Spacer()
                                Text("\(c.score)").font(CFont.mono(22, weight: .medium)).foregroundStyle(theme.accent)
                            }
                            .padding(.bottom, 9)
                            MiniBar(pct: c.scorePct, fill: theme.accent, track: ClassicTheme.dividerLight, height: 10)
                            Text(c.inline).font(CFont.mono(10)).foregroundStyle(ClassicTheme.faint).padding(.top, 8)
                        }
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
