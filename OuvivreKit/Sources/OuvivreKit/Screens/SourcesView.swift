import SwiftUI

/// Sources — every open-data reference used across the app: the country
/// profile sources for all supported countries, plus the livability sources.
struct SourcesView: View {
    @StateObject private var freshness = DatasetFreshness()
    @Environment(\.colorScheme) private var colorScheme
    private var pal: DetailColors { DetailColors(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Références des sources ouvertes utilisées pour les profils de pays et les classements de livabilité".uppercased())
                .font(CFont.rounded(14, weight: .bold))
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)

            // Grille non paresseuse : les deux cartes d'une rangée s'étirent à la
            // hauteur de la plus haute, leur contenu restant aligné en haut.
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                ForEach(Array(countriesWithSources.chunked(by: 2).enumerated()), id: \.offset) { _, pair in
                    GridRow {
                        ForEach(pair, id: \.country) { entry in
                            countryCard(entry.country, sources: entry.sources)
                        }
                        if pair.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
            .padding(.bottom, 28)

            freshnessCard
        }
        .task { await freshness.checkIfDue() }
    }

    private var countriesWithSources: [(country: String, sources: [ClassicStatic.CountrySource])] {
        ClassicStatic.countries.compactMap { country in
            guard let profile = ClassicStatic.countryProfiles[country], !profile.sources.isEmpty else { return nil }
            return (country, profile.sources)
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
                            .foregroundStyle(row.isStale ? ClassicTheme.accent : pal.ink)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 260, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private var freshnessRows: [(label: String, status: String, isStale: Bool)] {
        DatasetFreshness.datasets.map { dataset in
            let stale = freshness.staleDatasets.contains(dataset.label)
            return (dataset.label, stale ? "mise à jour disponible — retraiter via geo_pipeline/" : "à jour", stale)
        }
    }

    private func countryCard(_ country: String, sources: [ClassicStatic.CountrySource]) -> some View {
        sourceCard {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("\(ClassicStatic.countryFlags[country].map { $0 + " " } ?? "")\(country.uppercased())", color: pal.faint, font: CFont.rounded(13, weight: .medium), tracking: 1).padding(.bottom, 10)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func sourceCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(ClassicTheme.cardPadX)
            .background(pal.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.border, lineWidth: 1))
    }
}

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
