import Foundation

public enum NicoError: Error, Sendable, Equatable {
    /// The API answered with an error, e.g. `FORBIDDEN` / `ADMINISTRATOR_DELETE_VIDEO`.
    case api(errorCode: String, reasonCode: String?)
    /// Unexpected HTTP status with an unreadable body.
    case http(status: Int)
    /// The response did not have the expected shape (the API may have changed).
    case decoding(String)
    case network(String)
    /// No domand delivery for this video (premium/paid/members only, or not delivered to guests).
    case notPlayable
}

extension NicoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .api(let errorCode, let reasonCode):
            if let reasonCode, let message = Self.reasonMessages[reasonCode] { return message }
            return Self.errorMessages[errorCode] ?? "Niconico 返回错误：\(errorCode)"
        case .http(let status):
            return status >= 500 ? "Niconico 服务器暂时不可用（\(status)）" : "请求失败（HTTP \(status)）"
        case .decoding(let detail):
            return "无法解析 Niconico 的返回数据，接口可能变了：\(detail)"
        case .network(let detail):
            return "网络错误：\(detail)"
        case .notPlayable:
            return "这个视频没有可以播放的画质（可能需要会员、付费或登录）"
        }
    }

    // Reason and error codes follow yt-dlp's niconico extractor.
    private static let reasonMessages: [String: String] = [
        "ADMINISTRATOR_DELETE_VIDEO": "视频已被管理员删除",
        "RIGHT_HOLDER_DELETE_VIDEO": "视频应版权方要求已删除",
        "DELETED_CHANNEL_VIDEO": "频道已关闭，视频不可用",
        "DELETED_COMMUNITY_VIDEO": "社区已删除，视频不可用",
        "CHANNEL_MEMBER_ONLY": "仅频道会员可看",
        "HARMFUL_VIDEO": "敏感内容，需要登录",
        "HIDDEN_VIDEO": "视频已设为私密",
        "NOT_ALLOWED": "没有观看权限",
        "PPV_VIDEO": "付费视频",
        "PREMIUM_ONLY": "仅高级会员可看",
        "DOMESTIC_VIDEO": "仅限日本国内观看",
        "HIGH_RISK_COUNTRY_VIDEO": "所在地区无法观看",
    ]

    private static let errorMessages: [String: String] = [
        "FORBIDDEN": "页面不可用，请检查链接",
        "INVALID_PARAMETER": "视频不存在或已被删除",
        "NOT_FOUND": "视频不存在或已被删除",
        "MAINTENANCE": "Niconico 正在维护",
        "UNAUTHORIZED": "登录已失效，需要重新登录",
    ]
}
