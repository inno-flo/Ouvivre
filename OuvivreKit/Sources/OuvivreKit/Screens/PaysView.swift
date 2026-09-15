import SwiftUI

/// Étape 01 — Territoire: country search + suggestions + facts, and a
/// selection summary card with a "Définir les critères…" CTA.
public struct PaysView: View {
    @EnvironmentObject var theme: ClassicTheme
    @EnvironmentObject var state: ClassicState
    let derived: ClassicDerived

    public init(derived: ClassicDerived) { self.derived = derived }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("ÉTAPE 01 — TERRITOIRE", color: theme.accent).padding(.bottom, 12)
            Text("Choisissez un pays")
                .font(CFont.sans(theme.h1, weight: .semibold))
                .foregroundStyle(ClassicTheme.ink)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.bottom, 10)
            Text("Tapez un nom de pays. Ouvivre croise ensuite relief, hydrographie, climat, culture et mobilité pour en extraire une région, puis cinq villes.")
                .font(CFont.sans(15))
                .foregroundStyle(ClassicTheme.sub)
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.bottom, 26)

            searchCard
        }
    }

    private var searchCard: some View {
        Card(padding: theme.cardPad) {
            VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(derived.countryList) { c in
                        Button { state.setCountry(c.name) } label: {
                            Text(c.name)
                                .font(CFont.sans(13, weight: .medium))
                                .foregroundStyle(c.selected ? .white : ClassicTheme.body)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(c.selected ? ClassicTheme.ink : .white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(c.selected ? ClassicTheme.ink : ClassicTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Rectangle().fill(ClassicTheme.dividerLight).frame(height: 1).padding(.vertical, 20)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(derived.countryFacts) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.key).font(CFont.sans(13)).foregroundStyle(ClassicTheme.faint)
                            Text(f.value).font(CFont.sans(15, weight: .medium)).foregroundStyle(ClassicTheme.ink)
                        }
                    }
                }
            }
        }
    }

}

/// A responsive 2-column row that stacks to 1 column under `breakpoint`
/// points of available width — mirrors the dc export's CSS grids collapsing
/// naturally on narrow viewports. Implemented as a `Layout` (rather than a
/// `GeometryReader`) so it sizes correctly with variable-height children.
public struct AdaptiveTwoColumn<Left: View, Right: View>: View {
    var leftWeight: CGFloat = 1
    var rightWeight: CGFloat = 1
    var gap: CGFloat = 24
    var breakpoint: CGFloat = 640
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    public init(leftWeight: CGFloat = 1, rightWeight: CGFloat = 1, gap: CGFloat = 24, breakpoint: CGFloat = 640, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.leftWeight = leftWeight
        self.rightWeight = rightWeight
        self.gap = gap
        self.breakpoint = breakpoint
        self.left = left()
        self.right = right()
    }

    public var body: some View {
        TwoColumnLayout(leftWeight: leftWeight, rightWeight: rightWeight, gap: gap, breakpoint: breakpoint) {
            left
            right
        }
    }
}

struct TwoColumnLayout: Layout {
    var leftWeight: CGFloat
    var rightWeight: CGFloat
    var gap: CGFloat
    var breakpoint: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard subviews.count == 2 else { return .zero }
        if width < breakpoint {
            let l = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let r = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width, height: l.height + gap + r.height)
        } else {
            let lw = (width - gap) * leftWeight / (leftWeight + rightWeight)
            let rw = (width - gap) * rightWeight / (leftWeight + rightWeight)
            let l = subviews[0].sizeThatFits(ProposedViewSize(width: lw, height: nil))
            let r = subviews[1].sizeThatFits(ProposedViewSize(width: rw, height: nil))
            return CGSize(width: width, height: max(l.height, r.height))
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let width = bounds.width
        if width < breakpoint {
            let l = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: l.height))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + l.height + gap), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
        } else {
            let lw = (width - gap) * leftWeight / (leftWeight + rightWeight)
            let rw = (width - gap) * rightWeight / (leftWeight + rightWeight)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: lw, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + lw + gap, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: rw, height: nil))
        }
    }
}
