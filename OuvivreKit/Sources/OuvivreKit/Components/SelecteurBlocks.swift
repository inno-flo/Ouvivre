import SwiftUI


/// La liste de puces "pays" + fiche de faits — utilisée par `BigMacView` (bloc 1).
public struct PaysCountryBlock: View {
    @EnvironmentObject var state: ClassicState
    @EnvironmentObject var theme: ClassicTheme
    @Environment(\.colorScheme) private var colorScheme
    let derived: ClassicDerived
    let ink: Color
    let faint: Color
    /// `false` sur Big Mac : seules les capsules de choix du pays restent
    /// dans le bloc, la fiche de faits est déplacée dans l'inspecteur (voir
    /// `InspectorPanelView`/`ClassicRootView`).
    var showFacts: Bool = true
    var countryFont: Font = CFont.sans(13, weight: .medium)

    public init(derived: ClassicDerived, ink: Color, faint: Color, showFacts: Bool = true, countryFont: Font = CFont.sans(13, weight: .medium)) {
        self.countryFont = countryFont
        self.derived = derived
        self.ink = ink
        self.faint = faint
        self.showFacts = showFacts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(derived.countryList) { c in
                    Button { state.setCountry(c.name) } label: {
                        Text(c.name)
                            .font(countryFont)
                            .foregroundStyle(c.selected ? .white : ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(c.selected ? theme.accent : .clear)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(c.selected ? theme.accent : (colorScheme == .dark ? Color.white.opacity(0.3) : ClassicTheme.border), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if showFacts {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(derived.countryFacts) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.key).font(CFont.sans(13)).foregroundStyle(faint)
                            Text(f.value).font(CFont.sans(15, weight: .medium)).foregroundStyle(ink)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}


/// Les deux bascules d'exclusion (Territoires ultramarins / Corse),
/// utilisées par `BigMacView` (bloc 2).
public struct RegionExclusionToggles: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var excludeOverseas: Bool
    @Binding var excludeCorse: Bool
    let accent: Color
    let ink: Color
    var labelFont: Font = CFont.sans(13)

    public init(excludeOverseas: Binding<Bool>, excludeCorse: Binding<Bool>, accent: Color, ink: Color, labelFont: Font = CFont.sans(13)) {
        self.labelFont = labelFont
        self._excludeOverseas = excludeOverseas
        self._excludeCorse = excludeCorse
        self.accent = accent
        self.ink = ink
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Exclure les Territoires ultramarins", isOn: $excludeOverseas)
            row("Exclure la Corse", isOn: $excludeCorse)
        }
    }

    private func row(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn.wrappedValue ? accent : (colorScheme == .dark ? Color.white.opacity(0.08) : .white))
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(isOn.wrappedValue ? accent : (colorScheme == .dark ? Color.white.opacity(0.35) : ClassicTheme.border), lineWidth: 1))
                    .overlay {
                        if isOn.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                Text(label).font(labelFont).foregroundStyle(ink)
            }
        }
        .buttonStyle(.plain)
    }
}
