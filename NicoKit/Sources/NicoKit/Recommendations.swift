import Foundation

/// One batch from `nvapi.nicovideo.jp/v1/recommend`. Each call returns a different batch;
/// there is no paging, so "load more" means asking again and skipping videos already shown.
public struct RecommendationBatch: Sendable, Equatable {
    public var recommendID: String?
    public var videos: [VideoSummary]
}

public enum RecommendationRecipe: String, Sendable {
    /// The site's recommendations page (www.nicovideo.jp/recommendations); personalized
    /// when logged in. Up to 100 videos per call, each with a reason.
    case recommendations = "video_recommendation_recommend"
    /// The smaller block on the video top page (10 videos).
    case videoTop = "video_top_recommend"
}

extension RecommendationBatch {
    static func parse(_ data: Data) throws -> RecommendationBatch {
        struct Item: Decodable {
            struct Reason: Decodable { var tag: String? }
            var contentType: String
            var content: EssentialVideo
            var reason: Reason?
        }
        struct Payload: Decodable {
            var recommendId: String?
            var items: LossyArray<Item>
        }

        let payload = try NVAPI.decode(Payload.self, from: data)
        return RecommendationBatch(
            recommendID: payload.recommendId,
            videos: payload.items.elements
                .filter { $0.contentType == "video" }
                .compactMap { $0.content.summary(reasonTag: $0.reason?.tag) }
        )
    }
}

extension NicoClient {
    public func recommendations(
        _ recipe: RecommendationRecipe = .recommendations, limit: Int = 100
    ) async throws -> RecommendationBatch {
        var components = URLComponents(string: "https://nvapi.nicovideo.jp/v1/recommend")!
        components.queryItems = [
            .init(name: "recipeId", value: recipe.rawValue),
            .init(name: "site", value: "nicovideo"),
            .init(name: "limit", value: String(limit)),
            .init(name: "_frontendId", value: "6"),
            .init(name: "_frontendVersion", value: "0"),
        ]
        return try await getNVAPI(components.url!) { try RecommendationBatch.parse($0) }
    }
}
