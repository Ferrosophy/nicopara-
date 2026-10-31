import Foundation

/// Metadata of one video, as returned by the watch API (`/api/watch/v3_guest/{id}`).
public struct VideoInfo: Sendable, Equatable {
    public struct Counts: Sendable, Equatable, Codable {
        public var view: Int
        public var comment: Int
        public var mylist: Int
        public var like: Int
    }

    public enum Uploader: Sendable, Equatable {
        case user(id: String, name: String, iconURL: URL?)
        case channel(id: String, name: String, iconURL: URL?)

        public var name: String {
            switch self {
            case .user(_, let name, _), .channel(_, let name, _): name
            }
        }
    }

    /// Who may watch the video, from `payment.video`.
    public enum Access: String, Sendable, Equatable {
        case free
        case premiumOnly
        case channelMemberOnly
        case paid
    }

    /// One video or audio rendition offered by the domand (HLS) delivery.
    public struct Stream: Sendable, Equatable {
        public var id: String
        public var label: String?
        public var width: Int?
        public var height: Int?
        public var bitRate: Int?
        public var isAvailable: Bool
    }

    public var id: VideoID
    public var title: String
    /// Description as sent by the API; may contain HTML.
    public var descriptionHTML: String
    public var duration: Int
    public var registeredAt: Date?
    public var counts: Counts
    public var thumbnailURL: URL?
    public var uploader: Uploader?
    public var tags: [String]
    public var genre: String?
    public var access: Access
    public var videoStreams: [Stream]
    public var audioStreams: [Stream]

    /// Values the HLS access-rights request needs (M2). Nil when the video has no domand delivery.
    public var accessRightKey: String?
    public var watchTrackID: String?

    /// Where to fetch this video's comments (danmaku). Nil if the video has none.
    public var commentSource: CommentSource?
    /// Logged in only: whether the viewer has liked (いいね) this video / follows the uploader.
    public var isLiked: Bool?
    public var isFollowingUploader: Bool?
    /// The series this video belongs to, when the watch data says so (not sent to guests).
    public var series: SeriesRef?

    public var descriptionText: String { HTMLText.plain(descriptionHTML) }
}

/// The comment server and the opaque values it wants back (`comment.nvComment`).
public struct CommentSource: Sendable, Equatable {
    public var server: URL
    public var threadKey: String
    public var params: JSONValue
}

public struct SeriesRef: Sendable, Hashable {
    public var id: String
    public var title: String
}

extension VideoInfo {
    /// Parses a watch API response body. Throws ``NicoError/api(errorCode:reasonCode:)``
    /// when the API reports an error (deleted, private, members only, …).
    public static func parse(watchResponse data: Data) throws -> VideoInfo {
        let response: WatchResponse
        do {
            response = try JSONDecoder.nico.decode(WatchResponse.self, from: data)
        } catch {
            throw NicoError.decoding(String(describing: error))
        }
        guard response.meta.status == 200, let api = response.data, let video = api.video else {
            throw NicoError.api(
                errorCode: response.meta.errorCode ?? "UNKNOWN",
                reasonCode: response.data?.reasonCode
            )
        }
        guard let id = VideoID(parsing: video.id) else {
            throw NicoError.decoding("unexpected video id \(video.id)")
        }

        let uploader: Uploader? =
            if let channel = api.channel {
                .channel(id: channel.id.value, name: channel.name, iconURL: channel.thumbnail?.url)
            } else if let owner = api.owner {
                .user(id: owner.id.value, name: owner.nickname ?? "", iconURL: owner.iconUrl)
            } else {
                nil
            }

        let payment = api.payment?.video
        let access: Access =
            if payment?.isPpv == true || payment?.isContinuationBenefit == true { .paid }
            else if payment?.isAdmission == true { .channelMemberOnly }
            else if payment?.isPremium == true { .premiumOnly }
            else { .free }

        let thumbnail = video.thumbnail
        let domand = api.media?.domand

        return VideoInfo(
            id: id,
            title: video.title,
            descriptionHTML: video.description ?? "",
            duration: video.duration,
            registeredAt: video.registeredAt,
            counts: Counts(
                view: video.count?.view ?? 0,
                comment: video.count?.comment ?? 0,
                mylist: video.count?.mylist ?? 0,
                like: video.count?.like ?? 0
            ),
            thumbnailURL: thumbnail?.player ?? thumbnail?.largeUrl ?? thumbnail?.middleUrl ?? thumbnail?.url,
            uploader: uploader,
            tags: api.tag?.items.map(\.name) ?? [],
            genre: api.genre.flatMap { $0.isNotSet == true ? nil : $0.label },
            access: access,
            videoStreams: domand?.videos.map {
                Stream(id: $0.id, label: $0.label, width: $0.width, height: $0.height,
                       bitRate: $0.bitRate, isAvailable: $0.isAvailable)
            } ?? [],
            audioStreams: domand?.audios.map {
                Stream(id: $0.id, label: nil, width: nil, height: nil,
                       bitRate: $0.bitRate, isAvailable: $0.isAvailable)
            } ?? [],
            accessRightKey: domand?.accessRightKey,
            watchTrackID: api.client?.watchTrackId,
            commentSource: api.comment?.value?.nvComment.map {
                CommentSource(server: $0.server, threadKey: $0.threadKey, params: $0.params)
            },
            isLiked: video.viewer?.value?.like?.isLiked,
            isFollowingUploader: api.owner?.viewer?.value?.isFollowing,
            series: api.series?.value.map { SeriesRef(id: $0.id.value, title: $0.title) }
        )
    }
}

// MARK: - Wire format (only the fields we use)

private struct WatchResponse: Decodable {
    struct Meta: Decodable {
        var status: Int
        var errorCode: String?
    }

    struct Payload: Decodable {
        var reasonCode: String?
        var video: Video?
        var owner: Owner?
        var channel: Channel?
        var tag: Tags?
        var genre: Genre?
        var payment: Payment?
        var media: Media?
        var client: Client?
        // Extras: a surprise in their shape must not stop the video from loading.
        var comment: Lenient<Comment>?
        var series: Lenient<Series>?
    }

    struct Video: Decodable {
        struct Viewer: Decodable {
            struct Like: Decodable { var isLiked: Bool? }
            var like: Like?
        }
        var id: String
        var title: String
        var description: String?
        var duration: Int
        var registeredAt: Date?
        var count: Count?
        var thumbnail: Thumbnail?
        var viewer: Lenient<Viewer>?
    }

    struct Comment: Decodable {
        struct NvComment: Decodable {
            var server: URL
            var threadKey: String
            var params: JSONValue
        }
        var nvComment: NvComment?
    }

    struct Series: Decodable {
        var id: LooseID
        var title: String
    }

    struct Count: Decodable {
        var view: Int?
        var comment: Int?
        var mylist: Int?
        var like: Int?
    }

    struct Thumbnail: Decodable {
        var url: URL?
        var middleUrl: URL?
        var largeUrl: URL?
        var player: URL?
    }

    struct Owner: Decodable {
        struct Viewer: Decodable { var isFollowing: Bool? }
        var id: LooseID
        var nickname: String?
        var iconUrl: URL?
        var viewer: Lenient<Viewer>?
    }

    struct Channel: Decodable {
        struct Thumbnail: Decodable { var url: URL? }
        var id: LooseID
        var name: String
        var thumbnail: Thumbnail?
    }

    struct Tags: Decodable {
        struct Item: Decodable { var name: String }
        var items: [Item]
    }

    struct Genre: Decodable {
        var label: String?
        var isNotSet: Bool?
    }

    struct Payment: Decodable {
        struct Video: Decodable {
            var isPpv: Bool?
            var isAdmission: Bool?
            var isContinuationBenefit: Bool?
            var isPremium: Bool?
        }
        var video: Video?
    }

    struct Media: Decodable {
        var domand: Domand?
    }

    struct Domand: Decodable {
        struct VideoRendition: Decodable {
            var id: String
            var isAvailable: Bool
            var label: String?
            var width: Int?
            var height: Int?
            var bitRate: Int?
        }
        // Audio `label` is an object of localized strings, so it is not decoded.
        struct AudioRendition: Decodable {
            var id: String
            var isAvailable: Bool
            var bitRate: Int?
        }
        var videos: [VideoRendition]
        var audios: [AudioRendition]
        var accessRightKey: String?
    }

    struct Client: Decodable {
        var watchTrackId: String?
    }

    var meta: Meta
    var data: Payload?
}

extension JSONDecoder {
    static var nico: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
