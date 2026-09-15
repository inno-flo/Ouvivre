import SwiftUI

/// Fiche ville — detailed report for the top-ranked city (fixed: Annecy):
/// hero photo, stats grid, per-family match bars, monthly temperature
/// chart, and a sticky side panel with the global score, distances, warnings.
public struct VilleView: View {
    @EnvironmentObject var theme: ClassicTheme
    let derived: ClassicDerived
    private let ville = ClassicStatic.ville

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackLink(title: "← RETOUR AUX RÉSULTATS", color: theme.accent)
                .padding(.bottom, 14)

            AdaptiveTwoColumn(leftWeight: 1.35, rightWeight: 0.65, gap: theme.gap) {
                mainColumn
            } right: {
                sideColumn
            }
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if theme.showPhotos {
                PhotoPlaceholder(label: "vue de \(ville.name) — placeholder 16:9", height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))
                    .padding(.bottom, 20)
            }

            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(ville.name).font(CFont.sans(theme.h1, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                Text(ville.dept).font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.faint)
            }
            Text(ville.blurb)
                .font(CFont.sans(15))
                .foregroundStyle(ClassicTheme.body)
                .lineSpacing(4)
                .padding(.top, 12).padding(.bottom, 24)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 1)], spacing: 1) {
                ForEach(ville.stats) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.key).font(CFont.mono(9, weight: .medium)).tracking(1).foregroundStyle(ClassicTheme.faint)
                        Text(s.value).font(CFont.sans(19, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white)
                }
            }
            .background(ClassicTheme.border)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClassicTheme.border, lineWidth: 1))

            Eyebrow("CORRESPONDANCE PAR FAMILLE", color: ClassicTheme.faint).padding(.top, 28).padding(.bottom, 12)
            Card(padding: theme.cardPadX) {
                VStack(spacing: 0) {
                    ForEach(derived.villeFamilies) { f in
                        HStack(spacing: 14) {
                            Text(f.key).font(CFont.sans(13, weight: .medium)).foregroundStyle(ClassicTheme.ink).frame(width: 96, alignment: .leading)
                            MiniBar(pct: f.pct, fill: theme.accent, track: ClassicTheme.track, height: 6)
                            Text("\(f.value)").font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.ink).frame(width: 28, alignment: .trailing)
                            Text(f.note).font(CFont.mono(11)).foregroundStyle(ClassicTheme.faint).frame(width: 120, alignment: .trailing)
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                    }
                }
            }

            Eyebrow("CLIMAT — NORMALES MENSUELLES", color: ClassicTheme.faint).padding(.top, 28).padding(.bottom, 12)
            Card(padding: theme.cardPadX) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(derived.villeMonths) { m in
                        VStack(spacing: 6) {
                            Text("\(m.temp)°").font(CFont.mono(9)).foregroundStyle(ClassicTheme.sub)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(theme.accent)
                                .frame(height: m.height)
                            Text(m.label).font(CFont.mono(9)).foregroundStyle(ClassicTheme.faint2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 132, alignment: .bottom)
            }
        }
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("CORRESPONDANCE GLOBALE", color: ClassicTheme.darkPanelFaint).padding(.bottom, 8)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(ville.score)").font(CFont.mono(44, weight: .medium)).foregroundStyle(theme.accentLight)
                    Text("/100").font(CFont.mono(11)).foregroundStyle(ClassicTheme.darkPanelFaint)
                }
                Text("1re sur 5 villes retenues · 20 critères pondérés")
                    .font(CFont.sans(13)).foregroundStyle(ClassicTheme.darkPanelSub).padding(.top, 10)
                HStack(spacing: 8) {
                    OutlineButton("Sauvegarder", color: .white, border: Color(hex: 0x4A463F)) {}
                    AccentButton("Comparer", fill: theme.accent) {}
                }
                .padding(.top, 18)
            }
            .padding(theme.cardPad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClassicTheme.darkPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Card(padding: theme.cardPadX) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("À DISTANCE", color: ClassicTheme.faint).padding(.bottom, 10)
                    ForEach(ville.distances) { d in
                        HStack {
                            Text(d.key).font(CFont.sans(13)).foregroundStyle(ClassicTheme.body)
                            Spacer()
                            Text(d.value).font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }

            Card(padding: theme.cardPadX) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("POINTS D'ATTENTION", color: ClassicTheme.faint).padding(.bottom, 10)
                    ForEach(ville.warnings, id: \.self) { w in
                        HStack(alignment: .top, spacing: 9) {
                            Text("◆").font(.system(size: 10)).foregroundStyle(theme.accent)
                            Text(w).font(CFont.sans(13)).foregroundStyle(ClassicTheme.body).lineSpacing(2)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }
}

/// A tappable back-navigation caption, e.g. "← RETOUR AUX RÉSULTATS".
public struct BackLink: View {
    @EnvironmentObject var state: ClassicState
    let title: String
    let color: Color

    public init(title: String, color: Color) {
        self.title = title
        self.color = color
    }

    public var body: some View {
        Button { state.go(.meteo) } label: {
            Text(title).font(CFont.mono(10, weight: .medium)).tracking(1.6).foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}
