import SwiftUI

/// Étape 02 — Géographie: 5 weighted criteria sliders + a live-recomputed
/// "région la plus probante" panel and ranked runner-up regions.
public struct GeoView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    @EnvironmentObject var mapState: MapPanelState
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("ÉTAPE 03", color: theme.accent).padding(.bottom, 16)
            Text("Pondérez chaque critère de 0 (indifférent) à 5 (déterminant). Le classement des régions se recalcule à chaque mouvement.")
                .font(CFont.sans(15))
                .foregroundStyle(ClassicTheme.sub)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.bottom, 24)

            AdaptiveTwoColumn(gap: theme.gap) {
                slidersCard
            } right: {
                VStack(spacing: 16) {
                    regionHero
                    otherRegions
                }
            }
        }
    }

    private var slidersCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    exclusionToggle("Exclure les Territoires ultramarins", isOn: $state.excludeOverseas)
                    exclusionToggle("Exclure la Corse", isOn: $state.excludeCorse)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.cardPadX).padding(.vertical, theme.rowPad)
                .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                Eyebrow("PROXIMITÉS", color: ClassicTheme.faint)
                    .padding(.horizontal, theme.cardPadX).padding(.top, 14).padding(.bottom, 4)
                ForEach(derived.geoRows) { row in
                    CriterionRow(row: row) { state.setGeo(row.id, value: $0) }
                        .padding(.horizontal, theme.cardPadX).padding(.vertical, theme.rowPad)
                        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func exclusionToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn.wrappedValue ? theme.accent : .white)
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(isOn.wrappedValue ? theme.accent : ClassicTheme.border, lineWidth: 1))
                    .overlay {
                        if isOn.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                Text(label).font(CFont.sans(13)).foregroundStyle(ClassicTheme.body)
            }
        }
        .buttonStyle(.plain)
    }

    private var regionHero: some View {
        Button {
            if let nomRegion = derived.winningRegion()?.nomRegion { mapState.focusOnRegion(nomRegion) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("RÉGION LA PLUS PROBANTE", color: ClassicTheme.darkPanelFaint).padding(.bottom, 10)
                Text(derived.winningRegion()?.nomRegion ?? "—").font(CFont.sans(27, weight: .semibold)).foregroundStyle(.white)
                Text("Département le plus probant : \(derived.winningRegion()?.bestDept ?? "—")")
                    .font(CFont.sans(13)).foregroundStyle(ClassicTheme.darkPanelSub).padding(.top, 6)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(derived.topScore())").font(CFont.mono(34, weight: .medium)).foregroundStyle(theme.accentLight)
                    Text("/100 CORRESPONDANCE").font(CFont.mono(11)).foregroundStyle(ClassicTheme.darkPanelFaint)
                }
                .padding(.top, 18)
            }
            .padding(theme.cardPad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClassicTheme.darkPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var otherRegions: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("AUTRES DÉPARTEMENTS", color: ClassicTheme.faint).padding(.top, 14).padding(.horizontal, theme.cardPadX).padding(.bottom, 10)
                ForEach(derived.regionRows()) { r in
                    Button {
                        mapState.focusOnDepartement(r.name)
                    } label: {
                        HStack(spacing: 12) {
                            Text(r.rank).font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.faint2).frame(width: 18, alignment: .leading)
                            Text(r.name).font(CFont.sans(13, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                            Spacer()
                            MiniBar(pct: r.pct, fill: ClassicTheme.trackAlt).frame(width: 104, height: 4)
                            Text("\(r.score)").font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.ink).frame(width: 26, alignment: .trailing)
                        }
                        .padding(.horizontal, theme.cardPadX).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 6)
            }
        }
    }
}
