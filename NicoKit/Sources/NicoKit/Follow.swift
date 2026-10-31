import Foundation

/// A Niconico user as shown in lists (follow list, uploader of a feed item).
public struct NicoUser: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var nickname: String
    public var iconURL: URL?
    public var isPremium: Bool
    public var shortDescription: String?

    public init(id: String, nickname: String, iconURL: URL? = nil, isPremium: Bool = false, shortDescription: String? = nil) {
        self.id = id
        self.nickname = nickname
        self.iconURL = iconURL
        self.isPremium = isPremium
        self.shortDescription = shortDescription
    }
}

/// One page of `nvapi /v1/users/{id}/following/users`. The site returns follows newest first;
/// the cursor is the follow time of the last item, and `"cursorEnd"` after the last page.
public struct FollowingPage: Sendable, Equatable {
    public var users: [NicoUser]
    public var totalCount: Int?
    /// Pass to the next request; nil when there are no more pages.
    public var nextCursor: String?
}

/// A video upload from someone the user follows (`api.feed.nicovideo.jp` activities).
public struct FollowUpload: Sendable, Equatable, Identifiable {
    /// Activity ID, unique per feed entry.
    public var id: String
    public var videoID: VideoID
    public var title: String
    public var thumbnailURL: URL?
    public var duration: Int?
    public var postedAt: Date?
    public var uploaderID: String
    public var uploaderName: String
    public var uploaderIconURL: URL?
    /// "user" or "channel".
    public var uploaderType: String
}

public struct FollowFeedPage: Sendable, Equatable {
    public var uploads: [FollowUpload]
    public var nextCursor: String?
}

/// Sort keys of an uploader's video list, as on their page on the site (each asc or desc).
public enum UserVideoSort: String, Sendable, Codable, CaseIterable {
    case registeredAt
    case viewCount
    case lastCommentTime
    case commentCount
    case likeCount
    case mylistCount
    case duration
}

/// One page of an uploader's videos (`nvapi /v3/users/{id}/videos`).
public struct UserVideosPage: Sendable, Equatable {
    public var videos: [VideoSummary]
    public var totalCount: Int
    public var page: Int
    public var pageSize: Int

    public var canLoadMore: Bool { page * pageSize < totalCount }
}

// MARK: - Parsing

extension FollowingPage {
    static func parse(_ data: Data) throws -> FollowingPage {
        struct Item: Decodable {
            struct Icons: Decodable {
                var small: URL?
                var large: URL?
            }
            var id: LooseID
            var nickname: String
            var icons: Icons?
            var isPremium: Bool?
            var shortDescription: String?
        }
        struct Summary: Decodable {
            var followees: Int?
            var hasNext: Bool
            var cursor: String?
        }
        struct Payload: Decodable {
            var items: LossyArray<Item>
            var summary: Summary
        }

        let payload = try NVAPI.decode(Payload.self, from: data)
        let summary = payload.summary
        return FollowingPage(
            users: payload.items.elements.map {
                NicoUser(
                    id: $0.id.value, nickname: $0.nickname,
                    iconURL: $0.icons?.large ?? $0.icons?.small, isPremium: $0.isPremium ?? false,
                    shortDescription: $0.shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            },
            totalCount: summary.followees,
            nextCursor: summary.hasNext && summary.cursor != "cursorEnd" ? summary.cursor : nil
        )
    }
}

extension FollowFeedPage {
    /// The feed service has its own envelope: `{"code": "ok", "activities": [...], "nextCursor": …}`.
    static func parse(_ data: Data) throws -> FollowFeedPage {
        struct Activity: Decodable {
            struct Content: Decodable {
                struct Video: Decodable { var duration: Int? }
                var type: String
                var id: String
                var title: String
                var startedAt: Date?
                var video: Video?
            }
            struct Actor: Decodable {
                var id: String
                var type: String
                var name: String
                var iconUrl: URL?
            }
            var id: String
            var thumbnailUrl: URL?
            var content: Content
            var createdAt: Date?
            var actor: Actor
        }
        struct Response: Decodable {
            var code: String
            var activities: LossyArray<Activity>?
            var nextCursor: String?
        }

        let response: Response
        do {
            response = try JSONDecoder.nico.decode(Response.self, from: data)
        } catch {
            throw NicoError.decoding(String(describing: error))
        }
        guard response.code == "ok" else {
            throw NicoError.api(errorCode: response.code.uppercased(), reasonCode: nil)
        }
        let uploads = (response.activities?.elements ?? []).compactMap { activity -> FollowUpload? in
            guard activity.content.type == "video", let videoID = VideoID(parsing: activity.content.id) else { return nil }
            return FollowUpload(
                id: activity.id,
                videoID: videoID,
                title: activity.content.title,
                thumbnailURL: activity.thumbnailUrl,
                duration: activity.content.video?.duration,
                postedAt: activity.content.startedAt ?? activity.createdAt,
                uploaderID: activity.actor.id,
                uploaderName: activity.actor.name,
                uploaderIconURL: activity.actor.iconUrl,
                uploaderType: activity.actor.type
            )
        }
        return FollowFeedPage(uploads: uploads, nextCursor: response.nextCursor)
    }
}

extension UserVideosPage {
    static func parse(_ data: Data, page: Int, pageSize: Int) throws -> UserVideosPage {
        struct Item: Decodable { var essential: EssentialVideo }
        struct Payload: Decodable {
            var totalCount: Int
            var items: LossyArray<Item>
        }
        let payload = try NVAPI.decode(Payload.self, from: data)
        return UserVideosPage(
            videos: payload.items.elements.compactMap { $0.essential.summary() },
            totalCount: payload.totalCount, page: page, pageSize: pageSize
        )
    }
}

// MARK: - Requests

extension NicoClient {
    /// Who `userID` follows (`"me"` for the logged-in user), newest follow first.
    public func following(of userID: String = "me", cursor: String? = nil, pageSize: Int = 50) async throws -> FollowingPage {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v1/users/\(userID)/following/users")!
        components.queryItems = [.init(name: "pageSize", value: String(pageSize))]
        if let cursor { components.queryItems?.append(.init(name: "cursor", value: cursor)) }
        return try await getNVAPI(components.url!) { try FollowingPage.parse($0) }
    }

    /// Latest uploads from everyone the logged-in user follows, newest first (the site's
    /// follow timeline, videos only). Needs login.
    public func followFeed(cursor: String? = nil) async throws -> FollowFeedPage {
        var components = URLComponents(string: "https://api.feed.nicovideo.jp/v1/activities/followings/video")!
        components.queryItems = [.init(name: "context", value: "my_timeline")]
        if let cursor { components.queryItems?.append(.init(name: "cursor", value: cursor)) }
        return try await getNVAPI(components.url!) { try FollowFeedPage.parse($0) }
    }

    /// Videos uploaded by `userID`, newest first.
    public func userVideos(
        _ userID: String, sort: UserVideoSort = .registeredAt, order: SearchQuery.SortOrder = .desc,
        page: Int = 1, pageSize: Int = 30
    ) async throws -> UserVideosPage {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v3/users/\(userID)/videos")!
        components.queryItems = [
            .init(name: "sortKey", value: sort.rawValue),
            .init(name: "sortOrder", value: order.rawValue),
            .init(name: "pageSize", value: String(pageSize)),
            .init(name: "page", value: String(page)),
        ]
        return try await getNVAPI(components.url!) { try UserVideosPage.parse($0, page: page, pageSize: pageSize) }
    }

    /// A user's public profile (`nvapi /v1/users/{id}`).
    public func user(_ userID: String) async throws -> NicoUser {
        let account = try await getNVAPI(URL(string: "https://nvapi.nicovideo.jp/v1/users/\(userID)")!) {
            try Account.parse($0)
        }
        return NicoUser(id: account.id, nickname: account.nickname, iconURL: account.iconURL, isPremium: account.isPremium)
    }
}
