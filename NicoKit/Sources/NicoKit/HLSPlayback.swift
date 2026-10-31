import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What a player needs to play a video through domand (HLS, AES-128).
///
/// The master playlist and the AES key on `delivery.domand.nicovideo.jp` require the
/// `domand_bid` cookie set by the access-rights response (403 without it); pass ``cookies``
/// to the player (`AVURLAssetHTTPCookiesKey`). Segments on `asset.domand…` are signed URLs.
public struct HLSPlayback: Sendable, Equatable {
    public struct Cookie: Sendable, Equatable {
        public var name: String
        public var value: String
        public var domain: String
        public var path: String

        public var httpCookie: HTTPCookie? {
            HTTPCookie(properties: [
                .name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE",
            ])
        }
    }

    /// Master playlist with one variant per requested video rendition.
    public var url: URL
    public var cookies: [Cookie]

    public var httpCookies: [HTTPCookie] { cookies.compactMap(\.httpCookie) }
}

/// The quality to play: `automatic` lets the player switch between all available video
/// qualities; a `videoID` pins one; `audioOnly` skips the picture (listening mode).
public struct HLSSelection: Sendable, Equatable {
    public var videoID: String?
    public var audioID: String?
    public var audioOnly: Bool

    public init(videoID: String? = nil, audioID: String? = nil, audioOnly: Bool = false) {
        self.videoID = videoID
        self.audioID = audioID
        self.audioOnly = audioOnly
    }

    public static let automatic = HLSSelection()
}

extension HLSPlayback {
    /// Pairs every available video rendition with the best available audio, so the master
    /// playlist offers all qualities and the player can switch between them.
    static func outputs(for info: VideoInfo) -> [[String]] {
        outputs(for: info, selection: .automatic)
    }

    /// Which renditions to ask for. Tested against the site: one pair, several pairs, and
    /// audio alone all give a playable master playlist.
    static func outputs(for info: VideoInfo, selection: HLSSelection) -> [[String]] {
        let videos = info.videoStreams.filter(\.isAvailable)
        let audios = info.audioStreams.filter(\.isAvailable)
        let bestAudio = audios.max { ($0.bitRate ?? 0) < ($1.bitRate ?? 0) }
        let audio = selection.audioID.flatMap { id in audios.first { $0.id == id } } ?? bestAudio
        guard let audio else { return [] }
        if selection.audioOnly { return [[audio.id]] }
        if let videoID = selection.videoID, videos.contains(where: { $0.id == videoID }) {
            return [[videoID, audio.id]]
        }
        return videos.map { [$0.id, audio.id] }
    }

    /// Parses the access-rights response body plus its `Set-Cookie` headers.
    static func parse(accessRightsResponse data: Data, headers: [String: String], url: URL) throws -> HLSPlayback {
        struct Payload: Decodable { var contentUrl: URL }
        let contentURL = try NVAPI.decode(Payload.self, from: data).contentUrl

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).map {
            Cookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path)
        }
        return HLSPlayback(url: contentURL, cookies: cookies)
    }
}
