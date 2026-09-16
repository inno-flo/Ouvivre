import SwiftUI

public enum ClassicScreen: String, CaseIterable, Identifiable, Hashable {
    case pays, geo, geo2, meteo, affiner, ville, compare, profil, sources
    public var id: Self { self }
}

/// Root app state — mirrors the dc export's `Component` state/logic:
/// current screen, country query, and the geo/meteo/groups weight sliders
/// (0...5), all mutated in place and re-derived on read.
@MainActor
public final class ClassicState: ObservableObject {
    @Published public var screen: ClassicScreen = .pays
    @Published public var country: String = "France"
    @Published public var query: String = "France"
    @Published public var geo: [Int] = ClassicStatic.geo.map(\.1)
    @Published public var excludeOverseas: Bool = false
    @Published public var excludeCorse: Bool = false
    @Published public var meteo: [Int] = ClassicStatic.meteo.map(\.1)
    /// One weight array per group, indexed like `ClassicStatic.groups`.
    @Published public var groups: [[Int]] = ClassicStatic.groups.map { $0.rows.map(\.1) }

    public init() {}

    public func go(_ screen: ClassicScreen) { self.screen = screen }

    public func resetGeo() { geo = ClassicStatic.geo.map(\.1) }

    public func setGeo(_ index: Int, value: Int) { geo[index] = max(0, min(5, value)) }
    public func setMeteo(_ index: Int, value: Int) { meteo[index] = max(0, min(5, value)) }
    public func setGroup(_ groupIndex: Int, _ rowIndex: Int, value: Int) {
        groups[groupIndex][rowIndex] = max(0, min(5, value))
    }

    public func setCountry(_ name: String) { country = name; query = name }
}
