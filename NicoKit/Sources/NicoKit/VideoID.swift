/// A Niconico video ID such as `sm9`, `so38016254` or `nm2829323`.
public struct VideoID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public var description: String { rawValue }

    /// Extracts a video ID from a bare ID or a watch URL
    /// (`https://www.nicovideo.jp/watch/sm9`, `https://nico.ms/sm9`,
    /// `https://sp.nicovideo.jp/watch/sm9?ref=...`). Returns nil when no ID is found.
    public init?(parsing input: String) {
        // Swift Regex has no lookbehind, so the left boundary is a non-capturing group.
        let pattern = /(?:^|[^A-Za-z0-9])((?:sm|so|nm)[0-9]+)(?![0-9])/
        guard let match = input.firstMatch(of: pattern) else { return nil }
        rawValue = String(match.output.1)
    }

    public var watchURL: String { "https://www.nicovideo.jp/watch/\(rawValue)" }
}

/// Stored as the bare ID string, e.g. `"sm9"`.
extension VideoID: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = VideoID(parsing: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a video ID: \(raw)"))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
