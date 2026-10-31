import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One Niconico comment (shown as danmaku over the video, and in the 评论 list).
public struct NicoComment: Sendable, Equatable, Identifiable {
    public enum Position: Sendable { case scroll, top, bottom }
    public enum Size: Sendable { case medium, big, small }

    public var id: String
    public var number: Int
    /// Where in the video it was posted, in milliseconds.
    public var vposMs: Int
    public var body: String
    public var commands: [String]
    public var nicoruCount: Int
    public var postedAt: Date?
    /// The site's NG score: the lower, the more people have flagged it.
    public var score: Int
    /// "owner" (uploader), "main" or "easy".
    public var fork: String
    /// Anonymised poster ID (stable per video), for NG by user.
    public var userID: String = ""

    // Display settings from the commands ("ue", "big", "red", "#ff0000", …).
    public var position: Position {
        if commands.contains("ue") { return .top }
        if commands.contains("shita") { return .bottom }
        return .scroll
    }

    public var size: Size {
        if commands.contains("big") { return .big }
        if commands.contains("small") { return .small }
        return .medium
    }

    /// RGB as 0xRRGGBB; white when no color command.
    public var color: UInt32 {
        for command in commands {
            if let named = Self.namedColors[command] { return named }
            if command.hasPrefix("#"), command.count == 7, let value = UInt32(command.dropFirst(), radix: 16) {
                return value
            }
        }
        return 0xFFFFFF
    }

    /// The site's palette, including the premium-only names.
    static let namedColors: [String: UInt32] = [
        "white": 0xFFFFFF, "red": 0xFF0000, "pink": 0xFF8080, "orange": 0xFFC000,
        "yellow": 0xFFFF00, "green": 0x00FF00, "cyan": 0x00FFFF, "blue": 0x0000FF,
        "purple": 0xC000FF, "black": 0x000000,
        "white2": 0xCCCC99, "niconicowhite": 0xCCCC99, "red2": 0xCC0033, "truered": 0xCC0033,
        "pink2": 0xFF33CC, "orange2": 0xFF6600, "passionorange": 0xFF6600,
        "yellow2": 0x999900, "madyellow": 0x999900, "green2": 0x00CC66, "elementalgreen": 0x00CC66,
        "cyan2": 0x00CCCC, "blue2": 0x3399FF, "marinblue": 0x3399FF,
        "purple2": 0x6633CC, "nobleviolet": 0x6633CC, "black2": 0x666666,
    ]
}

extension NicoComment {
    /// Comments the site's default NG setting ("中") hides.
    public static let hiddenScore = -4800
    /// The lowest level (弱): anything below is hidden even with filtering at its weakest.
    /// Parsing keeps everything above this; the app applies the level the user picked.
    public static let weakestHiddenScore = -10000

    /// `POST {server}/v1/threads` response: all threads' comments, merged and sorted by time,
    /// minus the ones the site would hide.
    static func parse(threads data: Data) throws -> [NicoComment] {
        struct Thread: Decodable {
            struct Item: Decodable {
                var id: String
                var no: Int
                var vposMs: Int
                var body: String
                var commands: [String]?
                var nicoruCount: Int?
                var postedAt: Date?
                var score: Int?
                var userId: String?
            }
            var fork: String
            var comments: LossyArray<Item>
        }
        struct Payload: Decodable { var threads: [Thread] }

        let payload = try NVAPI.decode(Payload.self, from: data)
        return payload.threads
            .flatMap { thread in
                thread.comments.elements.map {
                    NicoComment(id: $0.id, number: $0.no, vposMs: $0.vposMs, body: $0.body,
                            commands: $0.commands ?? [], nicoruCount: $0.nicoruCount ?? 0,
                            postedAt: $0.postedAt, score: $0.score ?? 0, fork: thread.fork, userID: $0.userId ?? "")
                }
            }
            .filter { !$0.body.isEmpty }
            .sorted { $0.vposMs < $1.vposMs }
    }
}

extension NicoClient {
    /// The video's comments as the site's player loads them (the latest ones of each thread).
    /// Empty if the video has no comment source.
    public func comments(for info: VideoInfo) async throws -> [NicoComment] {
        guard let source = info.commentSource else { return [] }
        struct Body: Encodable {
            var params: JSONValue
            var threadKey: String
            var additionals: [String: String] = [:]
        }
        var request = request(source.server.appending(path: "v1/threads"), method: "POST")
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.baseURL, forHTTPHeaderField: "Origin")
        request.setValue("\(Self.baseURL)/", forHTTPHeaderField: "Referer")
        request.setValue("others", forHTTPHeaderField: "X-Client-Os-Type")
        request.httpBody = try JSONEncoder().encode(Body(params: source.params, threadKey: source.threadKey))
        let (data, response) = try await sendRaw(request)
        do {
            return try NicoComment.parse(threads: data)
        } catch NicoError.decoding(let detail) {
            if let status = response?.statusCode, !(200..<300).contains(status) { throw NicoError.http(status: status) }
            throw NicoError.decoding(detail)
        }
    }
}
