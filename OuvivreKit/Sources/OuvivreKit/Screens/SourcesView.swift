import SwiftUI
import AppKit

/// Sources — every open-data reference used across the app: the country
/// profile sources for all supported countries, plus the livability sources.
struct SourcesView: View {
    @ObservedObject private var freshness = DatasetFreshness.shared
    @Environment(\.colorScheme) private var colorScheme
    /// Base dont les instructions viennent d'être copiées (retour visuel temporaire).
    @State private var copiedLabel: String?
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
                HStack(spacing: 8) {
                    Eyebrow("\(ClassicStatic.countryFlags["France"] ?? "🇫🇷") FRAÎCHEUR DES DONNÉES", color: pal.faint, font: CFont.rounded(13, weight: .medium), tracking: 1)
                    Button {
                        Task { await freshness.forceCheck() }
                    } label: {
                        Group {
                            if freshness.isChecking {
                                Image(systemName: "progress.indicator").symbolEffect(.variableColor.iterative, isActive: true)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(pal.faint)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(freshness.isChecking)
                    .help("Vérifier maintenant la fraîcheur des données")
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 10)
                ForEach(freshnessRows, id: \.label) { row in
                    HStack(alignment: .top) {
                        Text(row.label).font(CFont.rounded(12)).foregroundStyle(pal.body)
                        Spacer()
                        statusView(row)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    @ViewBuilder
    private func statusView(_ row: (label: String, isStale: Bool)) -> some View {
        if freshness.checkingLabels.contains(row.label) {
            Image(systemName: "progress.indicator")
                .symbolEffect(.variableColor.iterative, isActive: true)
                .font(.system(size: 12))
                .foregroundStyle(pal.faint)
        } else if row.isStale {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(updateHelp(for: row.label), forType: .string)
                copiedLabel = row.label
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if copiedLabel == row.label { copiedLabel = nil }
                }
            } label: {
                HStack(alignment: .top, spacing: 5) {
                    if copiedLabel == row.label {
                        Text("Instructions copiées")
                            .font(CFont.mono(11, weight: .medium))
                            .foregroundStyle(pal.ink)
                        Image(systemName: "doc.on.clipboard.fill").foregroundStyle(.green)
                    } else {
                        Text("mise à jour disponible — retraiter via geo_pipeline/")
                            .font(CFont.mono(11, weight: .medium))
                            .foregroundStyle(ClassicTheme.accent)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 260, alignment: .trailing)
                        Image(systemName: "checkmark.circle.trianglebadge.exclamationmark.fill").foregroundStyle(.orange)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copier les instructions de mise à jour")
        } else if let date = freshness.verifiedAt[row.label] {
            HStack(spacing: 5) {
                Text("Vérification \(freshness.manuallyVerified.contains(row.label) ? "manuelle" : "automatique") faite le \(date.formatted(date: .long, time: .omitted))")
                    .font(CFont.mono(11, weight: .medium))
                    .foregroundStyle(pal.ink)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    /// Procédure de mise à jour (voir `geo_pipeline/README.md`).
    private func updateHelp(for label: String) -> String {
        let isCommunes = label == "Communes de France"
        let script = isCommunes ? "build_communes_data.py" : "build_culture_data.py"
        let output = isCommunes ? "communes_data.json" : "culture_scores.json"
        return """
        Une version plus récente de « \(label) » existe sur data.gouv.fr.
        Pour récupérer les données à jour :
        1. Dans le dossier geo_pipeline/, activer l'environnement Python (.venv avec requests).
        2. Lancer .venv/bin/python \(script) — il télécharge les données et écrit data/out/\(output).
        3. Copier ce fichier dans OuvivreKit/Sources/OuvivreKit/Resources/.
        4. Recompiler l'app.
        """
    }

    private var freshnessRows: [(label: String, isStale: Bool)] {
        DatasetFreshness.datasets.map { ($0.label, freshness.staleDatasets.contains($0.label)) }
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
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
