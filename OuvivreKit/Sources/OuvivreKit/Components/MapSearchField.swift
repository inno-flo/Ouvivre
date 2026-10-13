import SwiftUI
import MapKit

/// Recherche de lieux (villes, rues, adresses) avec suggestions d'autocomplétion,
/// biaisée vers la zone visible de la carte.
@MainActor
final class MapSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String, region: MKCoordinateRegion?) {
        if let region { completer.region = region }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestions = []
        } else {
            completer.queryFragment = query
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(5))
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
    }

    func resolve(query: String, region: MKCoordinateRegion?) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region { request.region = region }
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }
}

/// Champ de recherche compact ; la liste de suggestions s'affiche en dessous.
struct MapSearchField: View {
    @Environment(\.colorScheme) private var colorScheme
    private var c: DetailColors { DetailColors(colorScheme) }
    let region: MKCoordinateRegion?
    let onSelect: (MKMapItem) -> Void

    @StateObject private var model = MapSearchModel()
    @State private var query = ""
    @FocusState private var focused: Bool
    /// Suggestion surlignée au clavier (flèches haut/bas), `nil` si aucune.
    @State private var highlighted: Int?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(c.faint)
            TextField("Rechercher un lieu", text: $query)
                .textFieldStyle(.plain)
                .font(CFont.rounded(15))
                .foregroundStyle(c.ink)
                .focused($focused)
                .onChange(of: query) { _, new in
                    highlighted = nil
                    model.update(query: new, region: region)
                }
                .onChange(of: model.suggestions.count) { _, _ in highlighted = nil }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onSubmit {
                    if let index = highlighted, model.suggestions.indices.contains(index) {
                        choose(model.suggestions[index])
                        return
                    }
                    let text = query
                    Task { if let item = await model.resolve(query: text, region: region) { select(item) } }
                }
            if !query.isEmpty {
                Button { query = ""; model.suggestions = [] } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(c.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(width: 380)
        .background(c.border.opacity(0.5), in: Capsule())
        .overlay(alignment: .topLeading) {
            if focused && !model.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            choose(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.title).font(CFont.rounded(13, weight: .medium)).foregroundStyle(c.ink)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle).font(CFont.rounded(11)).foregroundStyle(c.faint)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(highlighted == index ? c.border.opacity(0.6) : .clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 280)
                .background(c.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(c.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .offset(y: 32)
            }
        }
    }

    private func moveHighlight(by step: Int) -> KeyPress.Result {
        let count = model.suggestions.count
        guard focused, count > 0 else { return .ignored }
        let next = (highlighted ?? (step > 0 ? -1 : count)) + step
        highlighted = min(count - 1, max(0, next))
        return .handled
    }

    private func choose(_ suggestion: MKLocalSearchCompletion) {
        Task { if let item = await model.resolve(suggestion) { select(item) } }
    }

    private func select(_ item: MKMapItem) {
        query = item.name ?? query
        model.suggestions = []
        focused = false
        onSelect(item)
    }
}
