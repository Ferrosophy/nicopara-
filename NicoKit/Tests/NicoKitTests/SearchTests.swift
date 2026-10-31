import Foundation
import Testing
@testable import NicoKit

@Suite struct SearchTests {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func defaultQueryOnlyAsksForJSON() {
        let url = SearchQuery(text: "ボカロ").url()
        #expect(url.path() == "/search/%E3%83%9C%E3%82%AB%E3%83%AD")
        #expect(query(url) == ["responseType": "json"])
    }

    @Test func encodesFiltersLikeTheSite() {
        var q = SearchQuery(mode: .tag, text: "VOCALOID")
        q.sort = .viewCount
        q.order = .asc
        q.kind = .channel
        q.length = .over20Minutes
        q.posted = .week
        q.genre = .musicSound
        q.startDate = "2024-01-01"
        q.endDate = "2024-01-31"
        let url = q.url(page: 3)

        #expect(url.path() == "/tag/VOCALOID")
        #expect(query(url) == [
            "responseType": "json", "sort": "viewCount", "order": "asc", "kind": "channel",
            "l_range": "2", "f_range": "2", "genre": "music_sound",
            "start": "2024-01-01", "end": "2024-01-31", "page": "3",
        ])
        #expect(q.hasFilters)
    }

    /// 人気 and おすすめ have no order on the site; sending one changes nothing, so leave it out.
    @Test func smartSortsHaveNoOrder() {
        var q = SearchQuery(text: "a")
        q.sort = .personalized
        q.order = .asc
        #expect(query(q.url()) == ["responseType": "json", "sort": "personalized"])
    }

    /// A slash in the keyword must not become a path separator.
    @Test func escapesSlash() {
        #expect(SearchQuery(text: "AC/DC").url().absoluteString.contains("/search/AC%2FDC?"))
    }

    // Real response for ボカロ, sort=registeredAt, l_range=1, page 2; captured 2026-10-30.
    @Test func parsesPage() throws {
        let url = try #require(Bundle.module.url(forResource: "search-page2", withExtension: "json", subdirectory: "Fixtures"))
        let page = try SearchPage.parse(Data(contentsOf: url))

        #expect(page.page == 2)
        #expect(page.maxPage == 157)
        #expect(page.totalCount == 1_154_865)
        #expect(page.hasNext)
        #expect(page.canLoadMore)
        #expect(page.videos.count == 32)
        #expect(page.videos.allSatisfy { $0.duration <= 300 }) // 5分以内
        #expect(!page.relatedTags.isEmpty)
    }

    @Test func queryRoundTrips() throws {
        var q = SearchQuery(text: "x")
        q.posted = .hour
        q.genre = .travelingOutdoor
        #expect(try JSONDecoder().decode(SearchQuery.self, from: JSONEncoder().encode(q)) == q)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveSearchTests {
    @Test func keywordDefaultSort() async throws {
        let page = try await NicoClient().search(SearchQuery(text: "ボカロ"))
        #expect(page.videos.count == 32)
        #expect(page.totalCount > 100_000)
    }

    @Test func tagNewestFirst() async throws {
        var q = SearchQuery(mode: .tag, text: "VOCALOID")
        q.sort = .registeredAt
        let page = try await NicoClient().search(q, page: 2)
        #expect(page.page == 2)
        let dates = page.videos.compactMap(\.registeredAt)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func noResults() async throws {
        let page = try await NicoClient().search(SearchQuery(text: "zqxjvkwpq这不可能有结果zqxj"))
        #expect(page.videos.isEmpty)
        #expect(!page.canLoadMore)
    }
}
