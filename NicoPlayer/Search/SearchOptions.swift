import Foundation
import NicoKit

/// Remembers the last-used sort and filters (everything except the search text) across launches.
enum SearchOptions {
    private static let key = "searchOptions"

    /// A new query for `text`, with the remembered sort and filters applied.
    static func query(mode: SearchQuery.Mode, text: String) -> SearchQuery {
        var query = SearchQuery(mode: mode, text: text)
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(SearchQuery.self, from: data) {
            query.sort = saved.sort
            query.order = saved.order
            query.kind = saved.kind
            query.length = saved.length
            query.posted = saved.posted
            query.genre = saved.genre
            query.startDate = saved.startDate
            query.endDate = saved.endDate
        }
        return query
    }

    static func remember(_ query: SearchQuery) {
        var options = query
        options.text = ""
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
