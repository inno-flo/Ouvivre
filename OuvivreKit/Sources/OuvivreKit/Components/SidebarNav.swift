import SwiftUI

/// The left rail: logo, "PARCOURS" (steps 1-4) + "OUTILS" (5-7) nav groups,
/// and a "recherche en cours" summary card pinned to the bottom.
public struct SidebarNav: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Circle().fill(theme.accent).frame(width: 10, height: 10)
                Text("OUVIVRE")
                    .font(CFont.mono(13, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(ClassicTheme.ink)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)

            group("PARCOURS", derived.navSteps)
            Rectangle().fill(ClassicTheme.border).frame(height: 1).padding(.horizontal, 14).padding(.vertical, 16)
            group("OUTILS", derived.navTools)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 7) {
                Eyebrow("RECHERCHE EN COURS", color: ClassicTheme.faint)
                Text("France · Savoie / Haute‑Savoie")
                    .font(CFont.sans(13, weight: .semibold))
                    .foregroundStyle(ClassicTheme.ink)
                Text("20 critères pondérés · 8 villes analysées")
                    .font(CFont.sans(12))
                    .foregroundStyle(ClassicTheme.sub)
            }
            .padding(12)
            .background(ClassicTheme.background)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClassicTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 14)

            if !derived.countrySources.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow("SOURCES", color: ClassicTheme.faint)
                    ForEach(derived.countrySources) { s in
                        Link(destination: URL(string: s.url) ?? URL(string: "https://")!) {
                            Text(s.label)
                                .font(CFont.sans(11))
                                .foregroundStyle(ClassicTheme.sub)
                                .underline()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
            }
        }
        .padding(.vertical, 22)
        .frame(width: 236)
        .background(ClassicTheme.sidebarBg)
        .overlay(alignment: .trailing) { Rectangle().fill(ClassicTheme.border).frame(width: 1) }
    }

    private func group(_ title: String, _ items: [NavItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(title, color: ClassicTheme.faint).padding(.horizontal, 20).padding(.bottom, 10)
            VStack(spacing: 2) {
                ForEach(items) { item in
                    Button { state.go(item.screen) } label: {
                        HStack(spacing: 9) {
                            Text(item.num).font(CFont.mono(10, weight: .medium)).opacity(0.6).frame(width: 14, alignment: .leading)
                            Text(item.label).font(CFont.sans(13, weight: .medium))
                            Spacer(minLength: 4)
                            if let meta = item.meta {
                                Text(meta).font(CFont.mono(10)).opacity(0.5)
                            }
                        }
                        .foregroundStyle(item.active ? Color.white : ClassicTheme.body)
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .background(item.active ? ClassicTheme.ink : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
    }
}
