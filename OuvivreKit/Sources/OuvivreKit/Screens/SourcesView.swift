import SwiftUI

/// Sources — every open-data reference used across the app: the country
/// profile sources for all supported countries, plus the livability sources.
public struct SourcesView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("SOURCES", color: theme.accent).padding(.bottom, 12)
            Text("Sources des données")
                .font(CFont.sans(theme.h2, weight: .semibold))
                .foregroundStyle(ClassicTheme.ink)
                .padding(.bottom, 8)
            Text("Références ouvertes utilisées pour les profils pays et les classements de livabilité.")
                .font(CFont.sans(15))
                .foregroundStyle(ClassicTheme.sub)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.bottom, 24)

            VStack(spacing: 14) {
                ForEach(ClassicStatic.countries, id: \.self) { country in
                    if let profile = ClassicStatic.countryProfiles[country], !profile.sources.isEmpty {
                        countryCard(country, sources: profile.sources)
                    }
                }
                livabilityCard
            }
        }
    }

    private func countryCard(_ country: String, sources: [ClassicStatic.CountrySource]) -> some View {
        Card(padding: theme.cardPadX) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(country.uppercased(), color: ClassicTheme.faint).padding(.bottom, 10)
                ForEach(sources) { s in
                    Link(destination: URL(string: s.url) ?? URL(string: "https://")!) {
                        Text(s.label)
                            .font(CFont.sans(13))
                            .foregroundStyle(ClassicTheme.body)
                            .underline()
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                }
            }
        }
    }

    private var livabilityCard: some View {
        Card(padding: theme.cardPadX, background: ClassicTheme.sidebarBg) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("LIVABILITÉ — CLASSEMENTS", color: ClassicTheme.faint).padding(.bottom, 10)
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
