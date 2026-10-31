import Foundation

/// One entry of the account's NG list (the site's NG設定): hide comments by word, by poster or
/// by command.
public struct NGItem: Sendable, Hashable {
    public enum Kind: String, Sendable { case word, user, command }
    public var kind: Kind
    public var value: String
}

/// The site's 共有NG levels: comments scored below the level's threshold are hidden.
public enum NGLevel: String, Sendable, Codable, CaseIterable {
    case none, weak, medium, strong

    /// Scores at or below this are hidden; nil means no score filtering.
    public var threshold: Int? {
        switch self {
        case .none: nil
        case .weak: -10000
        case .medium: -4800
        case .strong: -1000
        }
    }
}

/// What to hide, from 弹幕设置 → 屏蔽.
public struct DanmakuFilterOptions: Sendable, Equatable {
    public var ngLevel: NGLevel = .medium
    public var hideEasy = false
    public var hideOwner = false
    public var hideFixed = false
    public var hideScrolling = false
    public var hideColored = false
    /// Same text within a few seconds shows once; `countDuplicates` adds "×N".
    public var mergeDuplicates = false
    public var countDuplicates = true
    public var ng: [NGItem] = []

    public init() {}
}

public enum DanmakuFilter {
    /// Comments for the list (評論/弹幕 tab): NG and pools, not the on-screen type blocks.
    public static func forList(_ comments: [NicoComment], _ options: DanmakuFilterOptions) -> [NicoComment] {
        comments.filter { passesContent($0, options) }
    }

    /// Comments for the overlay, plus how many duplicates each kept comment stands for
    /// (only when merging). Input and output are sorted by time.
    public static func forOverlay(_ comments: [NicoComment], _ options: DanmakuFilterOptions,
                                  window: Int = 5000) -> (comments: [NicoComment], counts: [String: Int]) {
        var kept: [NicoComment] = []
        var counts: [String: Int] = [:]
        /// Body → (index in `kept`, its time) of the last kept comment with that text.
        var lastByBody: [String: (index: Int, vpos: Int)] = [:]
        for comment in comments where passesContent(comment, options) && passesType(comment, options) {
            if options.mergeDuplicates, let last = lastByBody[comment.body], comment.vposMs - last.vpos <= window {
                let id = kept[last.index].id
                counts[id, default: 1] += 1
                continue
            }
            lastByBody[comment.body] = (kept.count, comment.vposMs)
            kept.append(comment)
        }
        return (kept, options.countDuplicates ? counts.filter { $0.value > 1 } : [:])
    }

    static func passesContent(_ comment: NicoComment, _ options: DanmakuFilterOptions) -> Bool {
        if let threshold = options.ngLevel.threshold, comment.score <= threshold { return false }
        if options.hideEasy && comment.fork == "easy" { return false }
        if options.hideOwner && comment.fork == "owner" { return false }
        for item in options.ng {
            switch item.kind {
            case .word: if comment.body.localizedCaseInsensitiveContains(item.value) { return false }
            case .user: if !comment.userID.isEmpty && comment.userID == item.value { return false }
            case .command: if comment.commands.contains(item.value) { return false }
            }
        }
        return true
    }

    static func passesType(_ comment: NicoComment, _ options: DanmakuFilterOptions) -> Bool {
        switch comment.position {
        case .scroll: if options.hideScrolling { return false }
        case .top, .bottom: if options.hideFixed { return false }
        }
        if options.hideColored && comment.color != 0xFFFFFF { return false }
        return true
    }
}

extension NGItem {
    /// `GET nvapi /v1/users/me/ng-comments/client`. The site's code doesn't spell out the
    /// shape, so read the usual field names leniently and report the body if nothing fits.
    static func parseList(_ data: Data) throws -> [NGItem] {
        struct Item: Decodable {
            var type: String?
            var source: String?
            var value: String?
            var word: String?
        }
        struct Payload: Decodable {
            var items: LossyArray<Item>?
            var ngComments: LossyArray<Item>?
        }
        let payload = try NVAPI.decode(Payload.self, from: data)
        let raw = payload.items?.elements ?? payload.ngComments?.elements ?? []
        return raw.compactMap { item in
            guard let value = item.source ?? item.value ?? item.word, !value.isEmpty else { return nil }
            let kind: NGItem.Kind = switch item.type?.lowercased() {
            case "id", "user", "userid": .user
            case "command": .command
            default: .word
            }
            return NGItem(kind: kind, value: value)
        }
    }
}

extension NicoClient {
    /// The account's NG list as set on the website. Needs login.
    public func ngSettings() async throws -> [NGItem] {
        try await getNVAPI(URL(string: "https://nvapi.nicovideo.jp/v1/users/me/ng-comments/client")!) {
            try NGItem.parseList($0)
        }
    }
}
