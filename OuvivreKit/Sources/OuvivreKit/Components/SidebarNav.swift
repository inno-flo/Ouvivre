import SwiftUI

/// The native sidebar list: "Sélecteur" (steps) + "Outils" sections, plus a
/// "Sources" row — selection and highlighting are driven by `List`. Row and
/// header font sizes mirror the PierreVincent project's sidebar convention:
/// 13pt (`NSFont.systemFontSize`) for row labels, 11pt for section headers,
/// headers always staying smaller than the labels they group.
public struct SidebarNav: View {
    let derived: ClassicDerived
    let selection: Binding<ClassicScreen?>
    @EnvironmentObject private var state: ClassicState

    public init(derived: ClassicDerived, selection: Binding<ClassicScreen?>) {
        self.derived = derived
        self.selection = selection
    }

    public var body: some View {
        List(selection: selection) {
            Section {
                ForEach(derived.navSteps) { item in
                    NavItemRow(item: item).tag(item.screen)
                }
            } header: {
                Text("Sélecteur").foregroundStyle(.secondary)
            }
            Section {
                HStack(spacing: 9) {
                    Image(systemName: state.favoriteDepartementCodes.isEmpty ? "star" : "star.fill").frame(width: 16)
                    Text("Favoris").font(.system(size: 13, weight: state.screen == .favoris ? .bold : .regular))
                    Spacer(minLength: 4)
                    Text("\(state.favoriteDepartementCodes.count)").font(CFont.mono(10)).opacity(0.5)
                }
                .tag(ClassicScreen.favoris)
                HStack(spacing: 9) {
                    Image(systemName: "star").frame(width: 16)
                    Text("Favoris tests").font(.system(size: 13, weight: state.screen == .favorisTests ? .bold : .regular))
                    Spacer(minLength: 4)
                }
                .tag(ClassicScreen.favorisTests)
            } header: {
                Text("Comparateur").foregroundStyle(.secondary)
            }
            if !derived.countrySources.isEmpty {
                Section {
                    Text("Sources")
                        .font(.system(size: 13, weight: state.screen == .sources ? .bold : .regular))
                        .tag(ClassicScreen.sources)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct NavItemRow: View {
    let item: NavItem

    /// Icons for the "Sélecteur" screens only — matches the request's list;
    /// other rows (Outils, Sources) render without a leading icon.
    private var icon: String? {
        switch item.screen {
        case .bigMac: "chart.bar.horizontal.page"
        case .bigMacTests: "testtube.2"
        case .pays: "globe.europe.africa"
        case .geo2: "map"
        case .affiner: "bus"
        case .meteo: "thermometer.sun"
        case .ville: "mappin.and.ellipse"
        default: nil
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(systemName: icon).frame(width: 16)
            }
            Text(item.label).font(.system(size: 13, weight: item.active ? .bold : .regular))
            Spacer(minLength: 4)
            if let meta = item.meta {
                Text(meta).font(CFont.mono(10)).opacity(0.5)
            }
        }
    }
}
