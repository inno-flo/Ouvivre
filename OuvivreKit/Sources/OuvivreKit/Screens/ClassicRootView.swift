import SwiftUI

/// Entry point for the "classic" theme — owns `ClassicState` and lays out a
/// native sidebar + detail split, with the Sélecteur's details shown as a
/// native inspector panel.
public struct ClassicRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var state = ClassicState()
    @StateObject private var mapState = MapPanelState.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    public init() {}

    /// Shim binding for `List(selection:)`/`NavigationSplitView`, which need
    /// an optional selection — `state.screen` itself stays non-optional
    /// everywhere else, so a `nil` write (deselection) is simply ignored.
    private var sidebarSelectionBinding: Binding<SidebarDestination?> {
        Binding(
            get: { state.selectedDepartementCode.map { .departement($0) } ?? .screen(state.screen) },
            set: {
                switch $0 {
                case .screen(let screen): state.go(screen)
                case .departement(let code): state.goToDepartement(code)
                case nil: break
                }
            }
        )
    }

    /// Département favori affiché (vue Département), sinon `nil` — un
    /// département retiré des favoris n'est plus affiché.
    private var shownDepartementCode: String? {
        state.selectedDepartementCode.flatMap { state.favoriteDepartementCodes.contains($0) ? $0 : nil }
    }

    /// Le Sélecteur (carte plein cadre) est affiché : seul écran doté d'une
    /// carte, de boutons de toolbar et d'un inspecteur.
    private var isSelecteur: Bool { state.screen == .selecteur && shownDepartementCode == nil }

    /// L'inspecteur ne s'ouvre que sur action de l'utilisateur (bouton de la
    /// toolbar, menu) ou en cliquant un département sur la carte du Sélecteur
    /// (voir `SelecteurView`).
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { mapState.isVisible && isSelecteur },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.28)) { mapState.isVisible = newValue }
            }
        )
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarNav(selection: sidebarSelectionBinding)
        } detail: {
            Group {
                if let code = shownDepartementCode {
                    DepartementView(departementCode: code)
                        .id(code)
                } else if state.screen == .selecteur {
                    SelecteurView()
                } else {
                    ScrollView { content }
                        .frame(maxWidth: .infinity)
                }
            }
                .background((state.screen == .favoris || (state.screen == .sources && colorScheme == .dark)) ? DetailColors(colorScheme).window : Color.clear)
                .toolbar {
                    // Two separate, plain toolbar buttons (not the native
                    // combined MapZoomStepper, and no custom capsule/frame
                    // wrapping either — those both caused trouble before).
                    // Only meaningful while the Sélecteur's map is on screen.
                    if isSelecteur {
                        ToolbarItem {
                            Button { mapState.recenterOnCountry(state.country) } label: {
                                Image(systemName: "mappin.and.ellipse")
                            }
                            .help("Recentrer sur le pays sélectionné")
                        }
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
                            .help(inspectorBinding.wrappedValue ? "Masquer l'inspecteur" : "Afficher l'inspecteur")
                        }
                    }
                }
                .inspector(isPresented: inspectorBinding) {
                    InspectorPanelView()
                        .inspectorColumnWidth(min: 220, ideal: 320, max: 800)
                }
        }
        .navigationTitle("")
        .background(ClassicTheme.background)
        .environmentObject(state)
        .environmentObject(mapState)
        .onAppear { mapState.focusOnCountry(state.country) }
        .onChange(of: state.country) { _, newValue in mapState.focusOnCountry(newValue) }
    }

    /// Écrans défilants (Sources, Favoris) — le Sélecteur est rendu plein
    /// cadre, voir `body`.
    @ViewBuilder
    private var content: some View {
        Group {
            if state.screen == .favoris { FavorisView() } else { SourcesView() }
        }
        .padding(.horizontal, ClassicTheme.mainPadding)
        .padding(.top, ClassicTheme.mainPadding)
        .padding(.bottom, ClassicTheme.mainPaddingBottom)
        // Favoris occupe toute la largeur de la fenêtre (tableau et carte).
        .frame(maxWidth: state.screen == .favoris ? .infinity : 1340, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}
