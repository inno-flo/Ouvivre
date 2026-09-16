import SwiftUI

/// Mon espace — saved searches list + followed cities shortlist + a
/// criteria-profile summary card.
public struct ProfilView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("MON ESPACE", color: theme.accent).padding(.bottom, 24)

            AdaptiveTwoColumn(rightWeight: 0.7, gap: theme.gap) {
                savedList
            } right: {
                VStack(spacing: 14) {
                    shortlistCard
                    profileCard
                }
            }
        }
    }

    private var savedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("RECHERCHES ENREGISTRÉES", color: ClassicTheme.faint).padding(.bottom, 12)
            VStack(spacing: 12) {
                ForEach(ClassicStatic.saved, id: \.title) { s in
                    Card(padding: theme.cardPadX) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.title).font(CFont.sans(15, weight: .semibold)).foregroundStyle(ClassicTheme.ink)
                                Text(s.meta).font(CFont.sans(12)).foregroundStyle(ClassicTheme.faint)
                                FlowLayout(spacing: 6, rowSpacing: 6) {
                                    ForEach(s.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(CFont.mono(10))
                                            .foregroundStyle(ClassicTheme.sub)
                                            .padding(.horizontal, 7).padding(.vertical, 5)
                                            .background(ClassicTheme.cardAlt)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xE2DDD3), lineWidth: 1))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                .padding(.top, 6)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 10) {
                                Text("\(s.score)").font(CFont.mono(18, weight: .medium)).foregroundStyle(theme.accent)
                                Button { state.go(.meteo) } label: {
                                    Text("OUVRIR →").font(CFont.mono(10, weight: .medium)).foregroundStyle(ClassicTheme.faint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var shortlistCard: some View {
        Card(padding: theme.cardPadX) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("VILLES SUIVIES", color: ClassicTheme.faint).padding(.bottom, 10)
                ForEach(derived.shortlist) { c in
                    Button { state.go(.ville) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0xE9E5DC)).frame(width: 26, height: 26)
                            Text(c.name).font(CFont.sans(14, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                            Spacer()
                            Text("\(c.score)").font(CFont.mono(12, weight: .medium)).foregroundStyle(theme.accent)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var profileCard: some View {
        Card(padding: theme.cardPadX, background: ClassicTheme.sidebarBg) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("PROFIL DE CRITÈRES", color: ClassicTheme.faint).padding(.bottom, 8)
                Text("Montagne et lacs dominants, tolérance faible aux précipitations, exigence forte sur la desserte ferroviaire.")
                    .font(CFont.sans(13)).foregroundStyle(ClassicTheme.body).lineSpacing(3)
                Button { state.go(.geo) } label: {
                    Text("MODIFIER LES PONDÉRATIONS →").font(CFont.mono(11, weight: .medium)).foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
        }
    }
}
