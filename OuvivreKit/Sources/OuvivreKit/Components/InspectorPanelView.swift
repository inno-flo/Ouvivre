import SwiftUI

/// Contenu de l'inspecteur — panneau d'informations texte, sans carte
/// (retirée de l'inspecteur sur tous les écrans : chaque écran qui a besoin
/// d'une carte l'affiche en plein cadre dans le panneau central, avec ses
/// propres boutons de contrôle dans la toolbar).
public struct InspectorPanelView: View {
    @EnvironmentObject var theme: ClassicTheme
    let title: String
    let activeCultureCriteria: [String]

    public init(title: String, activeCultureCriteria: [String]) {
        self.title = title
        self.activeCultureCriteria = activeCultureCriteria
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("SÉLECTION", color: ClassicTheme.faint)
            Text(title)
                .font(CFont.sans(20, weight: .semibold))
                .foregroundStyle(ClassicTheme.ink)

            if !activeCultureCriteria.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("CRITÈRES CULTURE ACTIFS", color: ClassicTheme.faint)
                    ForEach(activeCultureCriteria, id: \.self) { label in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.accent)
                            Text(label)
                                .font(CFont.sans(14))
                                .foregroundStyle(ClassicTheme.body)
                        }
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClassicTheme.sidebarBg)
    }
}
