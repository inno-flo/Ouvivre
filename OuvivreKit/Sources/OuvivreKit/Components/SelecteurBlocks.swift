import SwiftUI

/// La liste de puces "pays" — utilisée par `SelecteurView` (bloc 1). La
/// fiche de faits du pays est affichée dans l'inspecteur (voir
/// `InspectorPanelView`).
struct PaysCountryBlock: View {
    @EnvironmentObject var state: ClassicState
    @Environment(\.colorScheme) private var colorScheme
    let ink: Color

    /// Pays dont la puce est masquée (données pas encore exploitées).
    private static let hiddenCountries: Set<String> = ["Suède", "Japon"]

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(ClassicStatic.countries.filter { !Self.hiddenCountries.contains($0) }, id: \.self) { name in
                let selected = name == state.country
                Button { state.country = name } label: {
                    // Drapeau devant le nom des pays dont les données sont chargées.
                    Text(ClassicStatic.countriesWithData.contains(name) ? [ClassicStatic.countryFlags[name], name].compactMap { $0 }.joined(separator: " ") : name)
                        .font(CFont.rounded(13, weight: .medium))
                        .foregroundStyle(selected ? .white : ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selected ? ClassicTheme.accent : .clear)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(selected ? ClassicTheme.accent : (colorScheme == .dark ? Color.white.opacity(0.3) : ClassicTheme.border), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Case à cocher + libellé du Sélecteur — bascules d'exclusion
/// (Territoires ultramarins / Corse) et tailles de commune (bloc 2).
struct SelecteurCheckbox: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    @Binding var isOn: Bool
    let ink: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn ? ClassicTheme.accent : (colorScheme == .dark ? Color.white.opacity(0.08) : .white))
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(isOn ? ClassicTheme.accent : (colorScheme == .dark ? Color.white.opacity(0.35) : ClassicTheme.border), lineWidth: 1))
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                Text(label).font(CFont.rounded(13, weight: .medium)).foregroundStyle(ink)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Petit bouton `info.circle` qui affiche une description au clic, via
/// `.popover` — utilisé par les 4 cases à cocher "taille de commune" du
/// bloc Régions.
struct InfoPopoverButton: View {
    let text: String
    let tint: Color
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text)
                .font(CFont.rounded(13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(12)
                .frame(width: 240, alignment: .leading)
        }
    }
}
