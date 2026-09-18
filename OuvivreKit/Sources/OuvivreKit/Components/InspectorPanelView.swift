import SwiftUI

/// Contenu de l'inspecteur — panneau d'informations texte, sans carte
/// (retirée de l'inspecteur sur tous les écrans : chaque écran qui a besoin
/// d'une carte l'affiche en plein cadre dans le panneau central, avec ses
/// propres boutons de contrôle dans la toolbar).
public struct InspectorPanelView: View {
    @EnvironmentObject var theme: ClassicTheme
    let title: String
    /// Critère (libellé + clé `CultureScores.criterionKeys`) et département
    /// courant — `nil` en dehors de Big Mac ou tant qu'aucun département
    /// n'a de code résolu (nom non trouvé dans `FranceGeoData`).
    let activeCultureCriteria: [(label: String, key: String)]
    let departementCode: String?

    public init(title: String, activeCultureCriteria: [(label: String, key: String)], departementCode: String?) {
        self.title = title
        self.activeCultureCriteria = activeCultureCriteria
        self.departementCode = departementCode
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow("SÉLECTION", color: ClassicTheme.faint)
                Text(title)
                    .font(CFont.sans(20, weight: .semibold))
                    .foregroundStyle(ClassicTheme.ink)

                ForEach(activeCultureCriteria, id: \.key) { criterion in
                    criterionSection(criterion)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClassicTheme.sidebarBg)
    }

    /// Le libellé du critère, suivi des noms des sites/événements de ce
    /// département pour ce critère (musées, festivals, ou "communes du site
    /// patrimonial remarquable" pour la Culture "Lieux du patrimoine").
    private func criterionSection(_ criterion: (label: String, key: String)) -> some View {
        let names = departementCode.map { CultureScores.names(forDepartementCode: $0, criterionKey: criterion.key) } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.accent)
                Text(criterion.label.uppercased())
                    .font(CFont.mono(11, weight: .semibold))
                    .foregroundStyle(ClassicTheme.faint)
            }
            if names.isEmpty {
                Text("Aucune donnée pour ce département.")
                    .font(CFont.sans(13))
                    .foregroundStyle(ClassicTheme.faint)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                            .font(CFont.sans(13))
                            .foregroundStyle(ClassicTheme.body)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}
