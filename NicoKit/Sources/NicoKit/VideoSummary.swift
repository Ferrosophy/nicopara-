import Foundation

/// One video in a list (recommendations, search results, …): enough for a card, not for playback.
/// Codable so the app can keep a list on disk.
public struct VideoSummary: Sendable, Equatable, Identifiable, Codable {
    public var id: VideoID
    public var title: String
    public var thumbnailURL: URL?
    public var duration: Int
    public var registeredAt: Date?
    public var counts: VideoInfo.Counts
    public var ownerName: String?
    public var ownerIconURL: URL?
    public var shortDescription: String?
    public var isChannelVideo: Bool
    public var isPaymentRequired: Bool
    /// Why it was recommended, e.g. the tag it matched. Nil outside recommendations.
    public var reasonTag: String?
}

/// The "essential" video object nvapi uses in lists (`content` in recommend, items in search).
struct EssentialVideo: Decodable {
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
        var listingUrl: URL?
        var nHdUrl: URL?
    }
    struct Owner: Decodable {
        var name: String?
        var iconUrl: URL?
    }

    var id: String
    var title: String
    var registeredAt: Date?
    var count: Count?
    var thumbnail: Thumbnail?
    var duration: Int?
    var shortDescription: String?
    var isChannelVideo: Bool?
    var isPaymentRequired: Bool?
    var owner: Owner?

    func summary(reasonTag: String? = nil) -> VideoSummary? {
        guard let id = VideoID(parsing: id) else { return nil }
        return VideoSummary(
            id: id,
            title: title,
            thumbnailURL: thumbnail?.nHdUrl ?? thumbnail?.largeUrl ?? thumbnail?.middleUrl ?? thumbnail?.url,
            duration: duration ?? 0,
            registeredAt: registeredAt,
            counts: .init(
                view: count?.view ?? 0, comment: count?.comment ?? 0,
                mylist: count?.mylist ?? 0, like: count?.like ?? 0
            ),
            ownerName: owner?.name,
            ownerIconURL: owner?.iconUrl,
            shortDescription: shortDescription,
            isChannelVideo: isChannelVideo ?? false,
            isPaymentRequired: isPaymentRequired ?? false,
            reasonTag: reasonTag
        )
    }
}

/// Decodes an array, skipping elements that fail (new content types, missing fields)
/// instead of failing the whole list.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(SkippedElement.self)
            }
        }
        self.elements = elements
    }
}

/// Decodes any JSON value, to step over an element ``LossyArray`` could not read.
struct SkippedElement: Decodable {}

extension VideoInfo {
    /// The list form of this video, e.g. to save it in a local list.
    public var summary: VideoSummary {
        VideoSummary(
            id: id, title: title, thumbnailURL: thumbnailURL, duration: duration,
            registeredAt: registeredAt, counts: counts,
            ownerName: uploader?.name,
            ownerIconURL: {
                switch uploader {
                case .user(_, _, let url), .channel(_, _, let url): url
                case nil: nil
                }
            }(),
            shortDescription: nil,
            isChannelVideo: { if case .channel = uploader { true } else { false } }(),
            isPaymentRequired: access != .free,
            reasonTag: nil
        )
    }
}
