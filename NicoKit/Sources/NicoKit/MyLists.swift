import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The logged-in user's lists that live on the account: あとで見る (watch later) and
// 視聴履歴 (watch history). Endpoints and fields are the website's (found in its code).

public struct WatchLaterItem: Sendable, Equatable, Identifiable {
    /// The list entry's own ID, needed to remove it (not the video ID).
    public var id: String
    public var video: VideoSummary
    public var memo: String?
    public var addedAt: Date?
}

public struct WatchLaterPage: Sendable, Equatable {
    public var items: [WatchLaterItem]
    public var totalCount: Int
    public var hasNext: Bool
    public var page: Int
}

public struct HistoryItem: Sendable, Equatable, Identifiable {
    public var video: VideoSummary
    public var lastViewedAt: Date?
    public var views: Int?

    public var id: VideoID { video.id }
}

public struct HistoryPage: Sendable, Equatable {
    public var items: [HistoryItem]
    public var nextCursor: String?
}

extension WatchLaterPage {
    /// `data.watchLater = {items: [{itemId, watchId, memo, addedAt, status, video}], totalCount, hasNext}`.
    static func parse(_ data: Data, page: Int) throws -> WatchLaterPage {
        struct Item: Decodable {
            var itemId: LooseID
            var memo: String?
            var addedAt: Date?
            var video: EssentialVideo
        }
        struct WatchLater: Decodable {
            var items: LossyArray<Item>
            var totalCount: Int?
            var hasNext: Bool?
        }
        struct Payload: Decodable { var watchLater: WatchLater }

        let list = try NVAPI.decode(Payload.self, from: data).watchLater
        return WatchLaterPage(
            items: list.items.elements.compactMap { item in
                item.video.summary().map {
                    WatchLaterItem(id: item.itemId.value, video: $0, memo: item.memo?.isEmpty == true ? nil : item.memo,
                                   addedAt: item.addedAt)
                }
            },
            totalCount: list.totalCount ?? 0,
            hasNext: list.hasNext ?? false,
            page: page
        )
    }
}

extension HistoryPage {
    /// `GET /v2/users/me/watch/history`. The site's code does not spell out the item shape, so
    /// this reads the common fields leniently and reports the raw body if nothing is readable.
    static func parse(_ data: Data) throws -> HistoryPage {
        struct Item: Decodable {
            var video: EssentialVideo
            var lastViewedAt: Date?
            var watchedAt: Date?
            var views: Int?
        }
        struct Payload: Decodable {
            var items: LossyArray<Item>
            var rawItems: [SkippedElement]
            var nextCursor: String?
            var cursor: String?
            var hasNext: Bool?

            enum CodingKeys: String, CodingKey { case items, nextCursor, cursor, hasNext }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                items = try container.decode(LossyArray<Item>.self, forKey: .items)
                rawItems = try container.decode([SkippedElement].self, forKey: .items)
                nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
                cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
                hasNext = try container.decodeIfPresent(Bool.self, forKey: .hasNext)
            }
        }

        let payload: Payload
        do {
            payload = try NVAPI.decode(Payload.self, from: data)
        } catch NicoError.decoding(let detail) {
            throw NicoError.decoding("\(detail) — \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        if payload.items.elements.isEmpty && !payload.rawItems.isEmpty {
            throw NicoError.decoding("历史记录格式不认识：\(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        let next = payload.nextCursor ?? payload.cursor
        return HistoryPage(
            items: payload.items.elements.compactMap { item in
                item.video.summary().map {
                    HistoryItem(video: $0, lastViewedAt: item.lastViewedAt ?? item.watchedAt, views: item.views)
                }
            },
            nextCursor: payload.hasNext == false ? nil : next
        )
    }
}

extension NicoClient {
    /// あとで見る, most recently added first.
    public func watchLater(page: Int = 1, pageSize: Int = 100) async throws -> WatchLaterPage {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v1/users/me/watch-later")!
        components.queryItems = [
            .init(name: "sortKey", value: "addedAt"),
            .init(name: "sortOrder", value: "desc"),
            .init(name: "pageSize", value: String(pageSize)),
            .init(name: "page", value: String(page)),
        ]
        return try await getNVAPI(components.url!) { try WatchLaterPage.parse($0, page: page) }
    }

    /// Adds a video to あとで見る. Adding one that is already there counts as success.
    public func addToWatchLater(_ id: VideoID, memo: String = "") async throws {
        var request = request(URL(string: "https://nvapi.nicovideo.jp/v1/users/me/watch-later")!, method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.baseURL, forHTTPHeaderField: "X-Request-With")
        var form = URLComponents()
        form.queryItems = [.init(name: "watchId", value: id.rawValue), .init(name: "memo", value: memo)]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        do {
            try await sendExpectingSuccess(request)
        } catch NicoError.api(let code, _) where code == "CONFLICT" {
            return
        }
    }

    /// Removes entries from あとで見る by their item IDs (``WatchLaterItem/id``).
    public func removeFromWatchLater(itemIDs: [String]) async throws {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v1/users/me/watch-later")!
        components.queryItems = [.init(name: "itemIds", value: itemIDs.joined(separator: ","))]
        var request = request(components.url!, method: "DELETE")
        request.setValue(Self.baseURL, forHTTPHeaderField: "X-Request-With")
        try await sendExpectingSuccess(request)
    }

    /// 視聴履歴, most recent first.
    public func watchHistory(cursor: String? = nil, limit: Int = 50) async throws -> HistoryPage {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v2/users/me/watch/history")!
        components.queryItems = [.init(name: "limit", value: String(limit))]
        if let cursor { components.queryItems?.append(.init(name: "cursor", value: cursor)) }
        return try await getNVAPI(components.url!) { try HistoryPage.parse($0) }
    }

    /// Tells Niconico a playback started, as the site's player does (`/v4/watch/{id}/side-effect`).
    /// This is what should count the view and add it to the account's 視聴履歴.
    public func reportPlayback(of info: VideoInfo) async throws {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v4/watch/\(info.id.rawValue)/side-effect")!
        if let trackID = info.watchTrackID {
            components.queryItems = [.init(name: "actionTrackId", value: trackID)]
        }
        var request = request(components.url!, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.baseURL, forHTTPHeaderField: "X-Request-With")
        request.httpBody = Data("{}".utf8)
        try await sendExpectingSuccess(request)
    }

    /// Sends a write request; succeeds on a 2xx `meta.status`.
    func sendExpectingSuccess(_ request: URLRequest) async throws {
        let (data, response) = try await sendRaw(request)
        if let status = response?.statusCode, (200..<300).contains(status), data.isEmpty { return }
        do {
            _ = try NVAPI.decodeStatus(from: data)
        } catch NicoError.decoding(let detail) {
            if let status = response?.statusCode, !(200..<300).contains(status) {
                throw NicoError.http(status: status)
            }
            throw NicoError.decoding(detail)
        }
    }
}
