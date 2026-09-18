import SwiftUI
import MapKit

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
    /// screen, and on Pays/Géographie 2, which embed their own full-bleed
    /// map instead of using the inspector — the toolbar icon stays visible
    /// on Pays regardless, it's just a no-op there for now.
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: {
                // Big Mac garde son propre indicateur (`bigMacInspectorVisible`,
                // par défaut fermé) plutôt que le `isVisible` partagé — sinon
                // l'inspecteur s'ouvrirait dès l'arrivée sur cet écran (valeur
                // par défaut de `isVisible` = true, utilisée par les autres
                // écrans). Il ne s'ouvre qu'en cliquant un département sur la
                // carte de Big Mac (voir `BigMacView`).
                let visible = state.screen == .bigMac ? mapState.bigMacInspectorVisible : mapState.isVisible
                return visible && state.screen != .sources && state.screen != .geo2 && state.screen != .pays
            },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.28)) {
                    if state.screen == .bigMac { mapState.bigMacInspectorVisible = newValue } else { mapState.isVisible = newValue }
                }
            }
        )
    }

    public var body: some View {
        let derived = ClassicDerived(state: state, theme: theme)

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarNav(derived: derived, selection: sidebarSelectionBinding)
        } detail: {
            Group {
                if state.screen == .pays {
                    PaysView(derived: derived)
                } else if state.screen == .geo2 {
                    GeoView2(derived: derived)
                } else if state.screen == .bigMac {
                    BigMacView(derived: derived)
                } else {
                    ScrollView { content(derived) }
                        .frame(maxWidth: .infinity)
                }
            }
                .toolbar {
                    // Two separate, plain toolbar buttons (not the native
                    // combined MapZoomStepper, and no custom capsule/frame
                    // wrapping either — those both caused trouble before).
                    // Only meaningful while Géographie 2's Map is on screen.
                    if state.screen == .geo2 || state.screen == .bigMac {
                        ToolbarItem {
                            Button { mapState.zoomOut() } label: {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .help("Dézoomer")
                        }
                        ToolbarItem {
                            Button { mapState.zoomIn() } label: {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .help("Zoomer")
                        }
                    }
                    ToolbarItem {
                        Menu {
                            ForEach(MapPlanType.allCases) { type in
                                Button { mapState.planType = type } label: { Label(type.label, systemImage: type.icon) }
                            }
                        } label: {
                            Image(systemName: "map")
                        }
                        .help("Type de carte")
                    }
                    ToolbarItem {
                        Button {
                            inspectorBinding.wrappedValue.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .help("Afficher/masquer la carte")
                    }
                }
                .inspector(isPresented: inspectorBinding) {
                    InspectorPanelView(
                        title: mapState.title,
                        activeCultureCriteria: state.screen == .bigMac ? derived.bigMacActiveCultureCriteria : [],
                        departementCode: FranceGeoData.departements.first { $0.nom == mapState.title }?.codeInsee
                    )
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
            case .pays: EmptyView() // rendered full-bleed outside content(), see body
            case .geo: GeoView(derived: derived)
            case .geo2: EmptyView() // rendered full-bleed outside content(), see body
            case .bigMac: EmptyView() // rendered full-bleed outside content(), see body
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
