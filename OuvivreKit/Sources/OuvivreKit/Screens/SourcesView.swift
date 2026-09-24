import SwiftUI

/// Sources — every open-data reference used across the app: the country
/// profile sources for all supported countries, plus the livability sources.
public struct SourcesView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    @StateObject private var freshness = DatasetFreshness()
    @Environment(\.colorScheme) private var colorScheme
    private var pal: DetailColors { DetailColors(colorScheme) }
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Références ouvertes utilisées pour les profils pays et les classements de livabilité.".uppercased())
                .font(CFont.rounded(14, weight: .bold))
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .leading), GridItem(.flexible(), spacing: 14, alignment: .leading)], spacing: 14) {
                ForEach(ClassicStatic.countries, id: \.self) { country in
                    if let profile = ClassicStatic.countryProfiles[country], !profile.sources.isEmpty {
                        countryCard(country, sources: profile.sources)
                    }
                }
            }
            .padding(.bottom, 14)

                .padding(.bottom, 14)

            freshnessCard
        }
        .onAppear {
            Task { await freshness.checkIfDue() }
        }
    }

    /// Fraîcheur des jeux de données "Big Mac" (communes + culture),
    /// vérifiée au plus une fois toutes les 15 jours auprès de l'API
    /// data.gouv.fr — voir `DatasetFreshness`. Le pipeline offline
    /// (`geo_pipeline/`) reste à relancer manuellement ; ceci se contente de
    /// signaler qu'une mise à jour amont est disponible.
    private var freshnessCard: some View {
        sourceCard {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("FRAÎCHEUR DES DONNÉES", color: pal.faint, font: CFont.rounded(13, weight: .medium), tracking: 1).padding(.bottom, 10)
                ForEach(freshnessRows, id: \.label) { row in
                    HStack(alignment: .top) {
                        Text(row.label).font(CFont.rounded(12)).foregroundStyle(pal.body)
                        Spacer()
                        Text(row.status)
                            .font(CFont.mono(11, weight: .medium))
                            .foregroundStyle(row.isStale ? theme.accent : pal.ink)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 260, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private var freshnessRows: [(label: String, status: String, isStale: Bool)] {
        let allLabels = ["Communes de France", "Musées (Basilic)", "Lieux du patrimoine (SPR)", "Festivals"]
        return allLabels.map { label in
            let stale = freshness.staleDatasets.contains(label)
            return (label, stale ? "mise à jour disponible — retraiter via geo_pipeline/" : "à jour", stale)
        }
    }

    private func countryCard(_ country: String, sources: [ClassicStatic.CountrySource]) -> some View {
        sourceCard {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(country.uppercased(), color: pal.faint, font: CFont.rounded(13, weight: .medium), tracking: 1).padding(.bottom, 10)
                ForEach(sources) { s in
                    Link(destination: URL(string: s.url) ?? URL(string: "https://")!) {
                        Text(s.label)
                            .font(CFont.rounded(13))
                            .foregroundStyle(pal.body)
                            .underline()
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) { Rectangle().fill(pal.divider).frame(height: 1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourceCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(theme.cardPadX)
            .background(pal.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.border, lineWidth: 1))
    }
}
