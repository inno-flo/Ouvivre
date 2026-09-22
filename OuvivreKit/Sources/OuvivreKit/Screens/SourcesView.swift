import SwiftUI

/// Sources — every open-data reference used across the app: the country
/// profile sources for all supported countries, plus the livability sources.
public struct SourcesView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    @StateObject private var freshness = DatasetFreshness()
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("SOURCES", color: theme.accent).padding(.bottom, 16)
            Text("Références ouvertes utilisées pour les profils pays et les classements de livabilité.")
                .font(CFont.rounded(15))
                .foregroundStyle(ClassicTheme.sub)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.bottom, 24)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .leading), GridItem(.flexible(), spacing: 14, alignment: .leading)], spacing: 14) {
                ForEach(ClassicStatic.countries, id: \.self) { country in
                    if let profile = ClassicStatic.countryProfiles[country], !profile.sources.isEmpty {
                        countryCard(country, sources: profile.sources)
                    }
                }
            }
            .padding(.bottom, 14)

            livabilityCard
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
        Card(padding: theme.cardPadX, background: ClassicTheme.sidebarBg) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("FRAÎCHEUR DES DONNÉES — BIG MAC", color: ClassicTheme.faint).padding(.bottom, 10)
                ForEach(freshnessRows, id: \.label) { row in
                    HStack(alignment: .top) {
                        Text(row.label).font(CFont.rounded(12)).foregroundStyle(ClassicTheme.body)
                        Spacer()
                        Text(row.status)
                            .font(CFont.mono(11, weight: .medium))
                            .foregroundStyle(row.isStale ? theme.accent : ClassicTheme.ink)
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
        Card(padding: theme.cardPadX) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(country.uppercased(), color: ClassicTheme.faint).padding(.bottom, 10)
                ForEach(sources) { s in
                    Link(destination: URL(string: s.url) ?? URL(string: "https://")!) {
                        Text(s.label)
                            .font(CFont.rounded(13))
                            .foregroundStyle(ClassicTheme.body)
                            .underline()
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) { Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var livabilityCard: some View {
        Card(padding: theme.cardPadX, background: ClassicTheme.sidebarBg) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("LIVABILITÉ — CLASSEMENTS", color: ClassicTheme.faint).padding(.bottom, 10)
                ForEach(ClassicStatic.rankings) { r in
                    HStack {
                        Text(r.key).font(CFont.rounded(12)).foregroundStyle(ClassicTheme.body)
                        Spacer()
                        Text(r.value).font(CFont.mono(11, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}
