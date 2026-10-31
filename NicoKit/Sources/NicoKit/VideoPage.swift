import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Everything the video page shows beyond the watch data: related videos, the uploader's
// profile, the series, and the like / follow actions. Endpoints are the website's.

/// An uploader's public numbers (`nvapi /v1/users/{id}`).
public struct UserProfile: Sendable, Equatable {
    public var user: NicoUser
    public var followerCount: Int
    public var followeeCount: Int
    /// Whether the logged-in user follows this user; nil for guests.
    public var isFollowing: Bool? = nil
}

/// A series (シリーズ, the site's 合集) with one page of its videos in series order.
public struct SeriesPage: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        /// Position in the series, from 1.
        public var order: Int
        public var video: VideoSummary
        public var id: VideoID { video.id }
    }

    public var series: SeriesRef
    public var totalCount: Int
    public var entries: [Entry]
    public var page: Int
    public var pageSize: Int

    public var canLoadMore: Bool { page * pageSize < totalCount }
}

/// Where a video sits in its series, for the 「合集 3/53」 card.
public struct SeriesPosition: Sendable, Equatable {
    public var series: SeriesRef
    public var order: Int?
    public var totalCount: Int?
}

extension UserProfile {
    static func parse(_ data: Data) throws -> UserProfile {
        struct User: Decodable {
            struct Icons: Decodable { var small: URL?; var large: URL? }
            var id: LooseID
            var nickname: String
            var icons: Icons?
            var isPremium: Bool?
            var followerCount: Int?
            var followeeCount: Int?
        }
        struct Relationships: Decodable {
            struct SessionUser: Decodable { var isFollowing: Bool? }
            var sessionUser: SessionUser?
        }
        struct Payload: Decodable {
            var user: User
            var relationships: Lenient<Relationships>?
        }
        let payload = try NVAPI.decode(Payload.self, from: data)
        let user = payload.user
        return UserProfile(
            user: NicoUser(id: user.id.value, nickname: user.nickname,
                           iconURL: user.icons?.large ?? user.icons?.small, isPremium: user.isPremium ?? false),
            followerCount: user.followerCount ?? 0,
            followeeCount: user.followeeCount ?? 0,
            isFollowing: payload.relationships?.value?.sessionUser?.isFollowing
        )
    }
}

extension SeriesPage {
    static func parse(_ data: Data, page: Int, pageSize: Int) throws -> SeriesPage {
        struct Item: Decodable {
            struct Meta: Decodable { var order: Int? }
            var meta: Meta?
            var video: EssentialVideo
        }
        struct Detail: Decodable {
            var id: LooseID
            var title: String
        }
        struct Payload: Decodable {
            var detail: Detail
            var totalCount: Int
            var items: LossyArray<Item>
        }
        let payload = try NVAPI.decode(Payload.self, from: data)
        let first = (page - 1) * pageSize + 1
        return SeriesPage(
            series: SeriesRef(id: payload.detail.id.value, title: payload.detail.title),
            totalCount: payload.totalCount,
            entries: payload.items.elements.enumerated().compactMap { index, item in
                item.video.summary().map { SeriesPage.Entry(order: item.meta?.order ?? first + index, video: $0) }
            },
            page: page, pageSize: pageSize
        )
    }
}

extension NicoClient {
    /// 相关推荐 for a video (the site's watch-page recommendation), videos only.
    public func relatedVideos(to id: VideoID, limit: Int = 25) async throws -> [VideoSummary] {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v1/recommend")!
        components.queryItems = [
            .init(name: "recipeId", value: "video_watch_recommendation"),
            .init(name: "videoId", value: id.rawValue),
            .init(name: "site", value: "nicovideo"),
            .init(name: "limit", value: String(limit)),
            .init(name: "_frontendId", value: "6"),
            .init(name: "_frontendVersion", value: "0"),
        ]
        return try await getNVAPI(components.url!) { try RecommendationBatch.parse($0).videos }
            .filter { $0.id != id }
    }

    public func userProfile(_ userID: String) async throws -> UserProfile {
        try await getNVAPI(URL(string: "https://nvapi.nicovideo.jp/v1/users/\(userID)")!) { try UserProfile.parse($0) }
    }

    public func series(_ seriesID: String, page: Int = 1, pageSize: Int = 100) async throws -> SeriesPage {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v2/series/\(seriesID)")!
        components.queryItems = [.init(name: "pageSize", value: String(pageSize)), .init(name: "page", value: String(page))]
        return try await getNVAPI(components.url!) { try SeriesPage.parse($0, page: page, pageSize: pageSize) }
    }

    /// The series a video is in. Guests don't get it in the watch data, but each item of the
    /// uploader's video list carries it, so look the video up among their latest uploads.
    public func seriesPosition(of info: VideoInfo) async throws -> SeriesPosition? {
        if let series = info.series {
            return SeriesPosition(series: series, order: nil, totalCount: nil)
        }
        guard case .user(let ownerID, _, _) = info.uploader else { return nil }
        struct Item: Decodable {
            struct Series: Decodable {
                var id: LooseID
                var title: String
                var order: Int?
            }
            var series: Series?
            var essential: EssentialVideo
        }
        struct Payload: Decodable { var items: LossyArray<Item> }
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v3/users/\(ownerID)/videos")!
        components.queryItems = [
            .init(name: "sortKey", value: "registeredAt"), .init(name: "sortOrder", value: "desc"),
            .init(name: "pageSize", value: "100"), .init(name: "page", value: "1"),
        ]
        let items = try await getNVAPI(components.url!) { try NVAPI.decode(Payload.self, from: $0).items.elements }
        guard let series = items.first(where: { $0.essential.id == info.id.rawValue })?.series else { return nil }
        let ref = SeriesRef(id: series.id.value, title: series.title)
        let total = try? await self.series(ref.id, pageSize: 1).totalCount
        return SeriesPosition(series: ref, order: series.order, totalCount: total)
    }

    /// いいね / 取消いいね (`POST` / `DELETE nvapi /v1/users/me/likes/items?videoId=`). Needs login.
    public func setLiked(_ liked: Bool, video id: VideoID) async throws {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v1/users/me/likes/items")!
        components.queryItems = [.init(name: "videoId", value: id.rawValue)]
        var request = request(components.url!, method: liked ? "POST" : "DELETE")
        request.setValue(Self.baseURL, forHTTPHeaderField: "X-Request-With")
        do {
            try await sendExpectingSuccess(request)
        } catch NicoError.api(let code, _) where code == "CONFLICT" || (!liked && code == "NOT_FOUND") {
            // Already in the requested state.
        }
    }

    /// Follow / unfollow a user (`user-follow-api.nicovideo.jp`). Needs login.
    public func setFollowing(_ following: Bool, user userID: String) async throws {
        let url = URL(string: "https://user-follow-api.nicovideo.jp/v1/user/followees/niconico-users/\(userID).json")!
        var request = request(url, method: following ? "POST" : "DELETE")
        request.setValue(Self.baseURL, forHTTPHeaderField: "X-Request-With")
        do {
            try await sendExpectingSuccess(request)
        } catch NicoError.api(let code, _) where code == "CONFLICT" || (!following && code == "NOT_FOUND") {
            // Already in the requested state.
        }
    }
}
