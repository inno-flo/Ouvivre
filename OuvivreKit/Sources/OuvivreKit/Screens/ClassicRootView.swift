import SwiftUI

/// Entry point for the "classic" theme — owns `ClassicTheme`/`ClassicState`
/// and lays out a native sidebar + detail split, with the map shown as a
/// native inspector panel.
public struct ClassicRootView: View {
    @StateObject private var theme = ClassicTheme()
    @StateObject private var state = ClassicState()
    @StateObject private var mapState = MapPanelState.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    public init() {}

    /// Shim binding for `List(selection:)`/`NavigationSplitView`, which need
    /// an optional selection — `state.screen` itself stays non-optional
    /// everywhere else, so a `nil` write (deselection) is simply ignored.
    private var sidebarSelectionBinding: Binding<ClassicScreen?> {
        Binding(get: { state.screen }, set: { if let screen = $0 { state.go(screen) } })
    }

    /// Mirrors the old `showMapPanel` rule: force-hidden on the Sources
    /// screen regardless of the user's last visibility choice.
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { mapState.isVisible && state.screen != .sources },
            set: { mapState.isVisible = $0 }
        )
    }

    public var body: some View {
        let derived = ClassicDerived(state: state, theme: theme)

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarNav(derived: derived, selection: sidebarSelectionBinding)
        } detail: {
            ScrollView { content(derived) }
                .frame(maxWidth: .infinity)
                .toolbar {
                    ToolbarItem {
                        Button {
                            inspectorBinding.wrappedValue.toggle()
                        } label: {
                            Image(systemName: "globe.europe.africa")
                        }
                        .help("Afficher/masquer la carte")
                    }
                }
                .inspector(isPresented: inspectorBinding) {
                    MapPanelView(mapState: mapState)
                        .inspectorColumnWidth(min: 220, ideal: 320, max: 800)
                }
        }
        .navigationTitle("")
        .background(ClassicTheme.background)
        .environmentObject(theme)
        .environmentObject(state)
        .environmentObject(mapState)
        .onAppear { mapState.focusOnCountry(state.country) }
        .onChange(of: state.country) { _, newValue in mapState.focusOnCountry(newValue) }
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
