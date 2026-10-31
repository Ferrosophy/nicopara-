import Foundation

/// A search on the site's own search pages (`/search/{keyword}`, `/tag/{tag}`), fetched as JSON
/// with `responseType=json`. Options and their URL values are exactly the website's, so the same
/// query gives the same results as nicovideo.jp. (The bare `nvapi /v2/search/video` rejects the
/// two default sorts, 人気 and おすすめ.)
public struct SearchQuery: Sendable, Hashable, Codable {
    public enum Mode: String, Sendable, Codable, CaseIterable {
        case keyword
        case tag
    }

    /// `sort` values, in the site's order.
    public enum SortKey: String, Sendable, Codable, CaseIterable {
        case hotLikeAndMylist      // ニコニコで人気 (default)
        case personalized          // あなたへのおすすめ
        case registeredAt          // 投稿日時
        case viewCount             // 再生数
        case lastCommentTime       // コメント日時
        case likeCount             // いいね！数
        case commentCount          // コメント数
        case mylistCount           // マイリスト登録数
        case duration              // 再生時間

        /// The two "smart" sorts take no order on the site.
        public var isOrderable: Bool { self != .hotLikeAndMylist && self != .personalized }
    }

    public enum SortOrder: String, Sendable, Codable, CaseIterable {
        case desc
        case asc
    }

    /// `kind`: 動画種別.
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case any
        case user
        case channel
    }

    /// `l_range`: 再生時間.
    public enum LengthRange: Int, Sendable, Codable, CaseIterable {
        case any = 0
        case under5Minutes = 1
        case over20Minutes = 2
    }

    /// `f_range`: 投稿日時, relative to now. Values are the site's (not in time order).
    public enum PostedRange: Int, Sendable, Codable, CaseIterable {
        case any = 0
        case hour = 4
        case day = 1
        case week = 2
        case month = 3
        case year = 5

        /// In the site's menu order.
        public static let allCases: [PostedRange] = [.any, .hour, .day, .week, .month, .year]
    }

    /// `genre`: ジャンル.
    public enum Genre: String, Sendable, Codable, CaseIterable {
        case all
        case entertainment
        case radio
        case musicSound = "music_sound"
        case dance
        case animal
        case nature
        case cooking
        case travelingOutdoor = "traveling_outdoor"
        case vehicle
        case sports
        case societyPoliticsNews = "society_politics_news"
        case technologyCraft = "technology_craft"
        case commentaryLecture = "commentary_lecture"
        case anime
        case game
        case other
        case r18
    }

    public var mode: Mode
    public var text: String
    public var sort: SortKey = .hotLikeAndMylist
    public var order: SortOrder = .desc
    public var kind: Kind = .any
    public var length: LengthRange = .any
    public var posted: PostedRange = .any
    public var genre: Genre = .all
    /// `start` / `end`: 投稿日 range as `yyyy-MM-dd` (Japan time), each optional.
    public var startDate: String?
    public var endDate: String?

    public init(mode: Mode = .keyword, text: String) {
        self.mode = mode
        self.text = text
    }

    /// True when any filter differs from the site's default (for a "filters on" badge).
    public var hasFilters: Bool {
        kind != .any || length != .any || posted != .any || genre != .all || startDate != nil || endDate != nil
    }

    /// The search page URL, with only non-default parameters, as the site builds them.
    public func url(page: Int = 1) -> URL {
        var path = CharacterSet.urlPathAllowed
        path.remove("/")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: path) ?? text
        var components = URLComponents(string: "https://www.nicovideo.jp/\(mode == .tag ? "tag" : "search")/\(encoded)")!

        var items = [URLQueryItem(name: "responseType", value: "json")]
        if sort != .hotLikeAndMylist { items.append(.init(name: "sort", value: sort.rawValue)) }
        if sort.isOrderable { items.append(.init(name: "order", value: order.rawValue)) }
        if kind != .any { items.append(.init(name: "kind", value: kind.rawValue)) }
        if length != .any { items.append(.init(name: "l_range", value: String(length.rawValue))) }
        if posted != .any { items.append(.init(name: "f_range", value: String(posted.rawValue))) }
        if genre != .all { items.append(.init(name: "genre", value: genre.rawValue)) }
        if let startDate { items.append(.init(name: "start", value: startDate)) }
        if let endDate { items.append(.init(name: "end", value: endDate)) }
        if page > 1 { items.append(.init(name: "page", value: String(page))) }
        components.queryItems = items
        return components.url!
    }
}

public struct SearchPage: Sendable, Equatable {
    public var videos: [VideoSummary]
    public var totalCount: Int
    public var page: Int
    /// The site stops at a fixed depth (157 pages of 32 at the time of writing).
    public var maxPage: Int
    public var hasNext: Bool
    /// Related tags the site suggests above the results.
    public var relatedTags: [String]

    public var canLoadMore: Bool { hasNext && page < maxPage }
}

extension SearchPage {
    static func parse(_ data: Data) throws -> SearchPage {
        struct Page: Decodable {
            struct Meta: Decodable {
                var status: Int
                var code: String?
            }
            struct Payload: Decodable { var response: Response }
            struct Response: Decodable {
                var search: Search
                var page: PageInfo

                enum CodingKeys: String, CodingKey {
                    case search = "$getSearchVideoV2"
                    case page
                }
            }
            struct Search: Decodable {
                struct Data: Decodable {
                    struct Additionals: Decodable {
                        struct Tag: Decodable { var text: String }
                        var tags: LossyArray<Tag>?
                    }
                    var totalCount: Int
                    var hasNext: Bool
                    var items: LossyArray<EssentialVideo>
                    var additionals: Additionals?
                }
                var data: Data
            }
            struct PageInfo: Decodable {
                struct Common: Decodable {
                    struct Pagination: Decodable {
                        var page: Int
                        var maxPage: Int
                    }
                    var pagination: Pagination
                }
                var common: Common
            }

            var meta: Meta
            var data: Payload?
        }

        let page: Page
        do {
            page = try JSONDecoder.nico.decode(Page.self, from: data)
        } catch {
            throw NicoError.decoding(String(describing: error))
        }
        // A search with no hits answers 404 / NOT_FOUND rather than an empty list.
        if page.meta.status == 404 {
            return SearchPage(videos: [], totalCount: 0, page: 1, maxPage: 0, hasNext: false, relatedTags: [])
        }
        guard page.meta.status == 200, let response = page.data?.response else {
            throw NicoError.api(errorCode: page.meta.code ?? "UNKNOWN", reasonCode: nil)
        }
        let search = response.search.data
        return SearchPage(
            videos: search.items.elements.compactMap { $0.summary() },
            totalCount: search.totalCount,
            page: response.page.common.pagination.page,
            maxPage: response.page.common.pagination.maxPage,
            hasNext: search.hasNext,
            relatedTags: search.additionals?.tags?.elements.map(\.text) ?? []
        )
    }
}

extension NicoClient {
    /// One page of results (32 videos). With a login, 「あなたへのおすすめ」 is personalized.
    public func search(_ query: SearchQuery, page: Int = 1) async throws -> SearchPage {
        try await getNVAPI(query.url(page: page)) { try SearchPage.parse($0) }
    }
}
