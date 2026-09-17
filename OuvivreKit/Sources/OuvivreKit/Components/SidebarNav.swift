import SwiftUI

/// The native sidebar list: "PARCOURS" (steps 1-4) + "OUTILS" (5-7) sections,
/// plus a "Sources" row — selection and highlighting are driven by `List`.
public struct SidebarNav: View {
    let derived: ClassicDerived
    let selection: Binding<ClassicScreen?>

    public init(derived: ClassicDerived, selection: Binding<ClassicScreen?>) {
        self.derived = derived
        self.selection = selection
    }

    public var body: some View {
        List(selection: selection) {
            Section("Sélecteur") {
                ForEach(derived.navSteps) { item in
                    NavItemRow(item: item).tag(item.screen)
                }
            }
            Section("Outils") {
                ForEach(derived.navTools) { item in
                    NavItemRow(item: item).tag(item.screen)
                }
            }
            if !derived.countrySources.isEmpty {
                Section {
                    Text("Sources")
                        .font(CFont.sans(13, weight: .medium))
                        .tag(ClassicScreen.sources)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct NavItemRow: View {
    let item: NavItem

    var body: some View {
        HStack(spacing: 9) {
            Text(item.label).font(CFont.sans(13, weight: .medium))
            Spacer(minLength: 4)
            if let meta = item.meta {
                Text(meta).font(CFont.mono(10)).opacity(0.5)
            }
        }
    }
}
