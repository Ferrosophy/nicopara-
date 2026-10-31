import Foundation

// The site's genre ranking (定番ランキング): the genre list with trend tags from nvapi, and each
// ranking page from the site's own page JSON (`/ranking/genre/{key}?responseType=json`).

/// One genre of the ranking, e.g. ゲーム.
public struct RankingGenre: Sendable, Hashable, Identifiable {
    /// The site's opaque key, e.g. "4eet3ca4".
    public var key: String
    /// The site's (Japanese) name, e.g. "ゲーム".
    public var label: String
    public var isImmoral: Bool
    public var trendTags: [String]

    public var id: String { key }
}

public enum RankingTerm: String, Sendable, Codable, CaseIterable {
    case hour
    case day = "24h"
    case week
    case month
    case total
}

public struct RankingPage: Sendable, Equatable {
    public var genre: String
    public var tag: String?
    public var videos: [VideoSummary]
    public var page: Int
    public var hasNext: Bool
}

extension RankingGenre {
    /// `v1/ranking/teiban/featured-keys/trend-tags`: every genre with its trend tags.
    static func parseList(_ data: Data) throws -> [RankingGenre] {
        struct Item: Decodable {
            var featuredKey: String
            var label: String
            var isImmoral: Bool?
            var trendTags: [String]?
        }
        struct Payload: Decodable { var items: LossyArray<Item> }
        return try NVAPI.decode(Payload.self, from: data).items.elements.map {
            RankingGenre(key: $0.featuredKey, label: $0.label, isImmoral: $0.isImmoral ?? false, trendTags: $0.trendTags ?? [])
        }
    }
}

extension RankingPage {
    static func parse(_ data: Data, page: Int) throws -> RankingPage {
        struct Response: Decodable {
            struct Meta: Decodable {
                var status: Int
                var code: String?
            }
            struct Payload: Decodable { var response: Inner }
            struct Inner: Decodable {
                var ranking: Ranking

                enum CodingKeys: String, CodingKey { case ranking = "$getTeibanRanking" }
            }
            struct Ranking: Decodable {
                struct Data: Decodable {
                    var label: String
                    var tag: String?
                    var items: LossyArray<EssentialVideo>
                    var hasNext: Bool?
                }
                var data: Data
            }
            var meta: Meta
            var data: Payload?
        }

        let response: Response
        do {
            response = try JSONDecoder.nico.decode(Response.self, from: data)
        } catch {
            throw NicoError.decoding(String(describing: error))
        }
        guard response.meta.status == 200, let ranking = response.data?.response.ranking.data else {
            throw NicoError.api(errorCode: response.meta.code ?? "UNKNOWN", reasonCode: nil)
        }
        return RankingPage(
            genre: ranking.label, tag: ranking.tag,
            videos: ranking.items.elements.compactMap { $0.summary() },
            page: page, hasNext: ranking.hasNext ?? false
        )
    }
}

extension NicoClient {
    /// All ranking genres with their trend tags. With a login, the account's settings decide
    /// whether the adult genre (例のソレ) is included.
    public func rankingGenres() async throws -> [RankingGenre] {
        try await getNVAPI(URL(string: "https://nvapi.nicovideo.jp/v1/ranking/teiban/featured-keys/trend-tags")!) {
            try RankingGenre.parseList($0)
        }
    }

    /// One page (100 videos) of a genre's ranking, optionally narrowed to a trend tag.
    public func ranking(_ genreKey: String, term: RankingTerm = .day, tag: String? = nil, page: Int = 1) async throws -> RankingPage {
        var components = URLComponents(string: "\(Self.baseURL)/ranking/genre/\(genreKey)")!
        components.queryItems = [.init(name: "term", value: term.rawValue)]
        if let tag { components.queryItems?.append(.init(name: "tag", value: tag)) }
        if page > 1 { components.queryItems?.append(.init(name: "page", value: String(page))) }
        components.queryItems?.append(.init(name: "responseType", value: "json"))
        return try await getNVAPI(components.url!) { try RankingPage.parse($0, page: page) }
    }

    /// Tag names matching what the user typed, from the site's tag suggestions.
    public func suggestTags(_ text: String) async throws -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let encoded = trimmed.replacingOccurrences(of: "　", with: " ").addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        struct Response: Decodable { var candidates: [String]? }
        return try await getNVAPI(URL(string: "https://sug.search.nicovideo.jp/suggestion/expand/\(encoded)")!) { data in
            do {
                return (try JSONDecoder().decode(Response.self, from: data).candidates ?? [])
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } catch {
                throw NicoError.decoding(String(describing: error))
            }
        }
    }
}
