import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Entry point for the "classic" theme — owns `ClassicTheme`/`ClassicState`
/// and lays out the sidebar + main content, collapsing the sidebar into a
/// horizontal top bar on narrow (iPhone) widths.
public struct ClassicRootView: View {
    @StateObject private var theme = ClassicTheme()
    @StateObject private var state = ClassicState()
    @StateObject private var mapState = MapPanelState.shared
    @State private var mapPanelWidth: CGFloat = 300
    @State private var mapPanelWidthAtDragStart: CGFloat = 300
    @State private var hasSetInitialMapPanelWidth = false

    private let mapPanelMinWidth: CGFloat = 220
    private let mapPanelMaxWidth: CGFloat = 560
    private let sidebarWidth: CGFloat = 236

    public init() {}

    private var showMapPanel: Bool { mapState.isVisible && state.screen != .sources }

    public var body: some View {
        GeometryReader { geo in
            let derived = ClassicDerived(state: state, theme: theme)
            let compact = geo.size.width < 720

            Group {
                if compact {
                    VStack(spacing: 0) {
                        CompactNavBar(derived: derived)
                        ScrollView { content(derived) }
                        if showMapPanel {
                            MapPanelView(mapState: mapState).frame(height: 260)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        SidebarNav(derived: derived)
                        ScrollView { content(derived) }
                        if showMapPanel {
                            resizeHandle
                            MapPanelView(mapState: mapState).frame(width: mapPanelWidth)
                        } else if state.screen != .sources {
                            reopenTab
                        }
                    }
                    .onAppear { setInitialMapPanelWidth(totalWidth: geo.size.width) }
                    .onChange(of: geo.size.width) { _, newValue in setInitialMapPanelWidth(totalWidth: newValue) }
                }
            }
        }
        .background(ClassicTheme.background)
        .environmentObject(theme)
        .environmentObject(state)
        .environmentObject(mapState)
        .onAppear { mapState.focusOnCountry(state.country) }
        .onChange(of: state.country) { _, newValue in mapState.focusOnCountry(newValue) }
    }

    /// Sets the map panel to a 2/3 content – 1/3 carte split on first layout,
    /// leaving it alone afterwards so a manual resize (`resizeHandle`) sticks.
    private func setInitialMapPanelWidth(totalWidth: CGFloat) {
        guard !hasSetInitialMapPanelWidth, totalWidth > 0 else { return }
        hasSetInitialMapPanelWidth = true
        let available = max(0, totalWidth - sidebarWidth)
        mapPanelWidth = min(mapPanelMaxWidth, max(mapPanelMinWidth, available / 3))
        mapPanelWidthAtDragStart = mapPanelWidth
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(ClassicTheme.border)
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let proposed = mapPanelWidthAtDragStart - value.translation.width
                                mapPanelWidth = min(mapPanelMaxWidth, max(mapPanelMinWidth, proposed))
                            }
                            .onEnded { _ in mapPanelWidthAtDragStart = mapPanelWidth }
                    )
                    #if os(macOS)
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    #endif
            )
    }

    private var reopenTab: some View {
        Button { mapState.isVisible = true } label: {
            Image(systemName: "map")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClassicTheme.faint)
                .frame(width: 28, height: 44)
        }
        .buttonStyle(.plain)
        .background(ClassicTheme.sidebarBg)
        .overlay(alignment: .leading) { Rectangle().fill(ClassicTheme.border).frame(width: 1) }
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
