import SwiftUI

/// Entry point for the "classic" theme — owns `ClassicTheme`/`ClassicState`
/// and lays out the sidebar + main content, collapsing the sidebar into a
/// horizontal top bar on narrow (iPhone) widths.
public struct ClassicRootView: View {
    @StateObject private var theme = ClassicTheme()
    @StateObject private var state = ClassicState()

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let derived = ClassicDerived(state: state, theme: theme)
            let compact = geo.size.width < 720

            Group {
                if compact {
                    VStack(spacing: 0) {
                        CompactNavBar(derived: derived)
                        ScrollView { content(derived) }
                    }
                } else {
                    HStack(spacing: 0) {
                        SidebarNav(derived: derived)
                        ScrollView { content(derived) }
                    }
                }
            }
        }
        .background(ClassicTheme.background)
        .environmentObject(theme)
        .environmentObject(state)
    }

    @ViewBuilder
    private func content(_ derived: ClassicDerived) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state.screen {
            case .pays: PaysView(derived: derived)
            case .geo: GeoView(derived: derived)
            case .meteo: MeteoView(derived: derived)
            case .affiner: AffinerView(derived: derived)
            case .ville: VilleView(derived: derived)
            case .compare: CompareView(derived: derived)
            case .profil: ProfilView(derived: derived)
            case .sources: SourcesView(derived: derived)
            }
        }
        .padding(.horizontal, theme.mainPadding)
        .padding(.top, theme.mainPadding)
        .padding(.bottom, theme.mainPaddingBottom)
        .frame(maxWidth: 1340, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

/// Horizontally-scrolling nav used instead of the sidebar on iPhone-width layouts.
private struct CompactNavBar: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    let derived: ClassicDerived

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(derived.navSteps + derived.navTools) { item in
                    Button { state.go(item.screen) } label: {
                        Text(item.label)
                            .font(CFont.sans(13, weight: .medium))
                            .foregroundStyle(item.active ? .white : ClassicTheme.body)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(item.active ? ClassicTheme.ink : ClassicTheme.sidebarBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(ClassicTheme.sidebarBg)
        .overlay(alignment: .bottom) { Rectangle().fill(ClassicTheme.border).frame(height: 1) }
    }
}
