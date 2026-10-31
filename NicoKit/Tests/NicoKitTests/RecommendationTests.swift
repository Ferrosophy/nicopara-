import Foundation
import Testing
@testable import NicoKit

@Suite struct RecommendationTests {
    // Real guest response (limit=5), captured 2026-10-30.
    @Test func parsesBatch() throws {
        let url = try #require(Bundle.module.url(forResource: "recommend-guest", withExtension: "json", subdirectory: "Fixtures"))
        let batch = try RecommendationBatch.parse(Data(contentsOf: url))

        #expect(batch.recommendID?.isEmpty == false)
        #expect(batch.videos.count == 5)
        for video in batch.videos {
            #expect(!video.title.isEmpty)
            #expect(video.thumbnailURL != nil)
            #expect(video.duration > 0)
            #expect(video.registeredAt != nil)
        }
    }

    /// The app caches the feed on disk; a summary must survive a round trip unchanged.
    @Test func summaryRoundTrips() throws {
        let url = try #require(Bundle.module.url(forResource: "recommend-guest", withExtension: "json", subdirectory: "Fixtures"))
        let videos = try RecommendationBatch.parse(Data(contentsOf: url)).videos
        let decoded = try JSONDecoder().decode([VideoSummary].self, from: JSONEncoder().encode(videos))
        #expect(decoded == videos)
        #expect(String(decoding: try JSONEncoder().encode(VideoID(parsing: "sm9")!), as: UTF8.self) == #""sm9""#)
    }

    /// Unknown content types and broken items are skipped, the rest still load.
    @Test func skipsUnknownItems() throws {
        let body = Data("""
        {"meta":{"status":200},"data":{"recommendId":"1","items":[
          {"id":"lv1","contentType":"live","recommendType":"recommend","content":{"id":"lv1"}},
          {"id":"broken","contentType":"video","content":{}},
          {"id":"sm9","contentType":"video","recommendType":"recommend","reason":{"tag":"音楽"},
           "content":{"id":"sm9","title":"t","duration":320,"registeredAt":"2007-03-06T00:33:00+09:00",
                      "count":{"view":1,"comment":2,"mylist":3,"like":4},
                      "thumbnail":{"url":"https://example.com/a","nHdUrl":"https://example.com/hd"},
                      "owner":{"name":"中の","iconUrl":"https://example.com/i"}}}
        ]}}
        """.utf8)
        let batch = try RecommendationBatch.parse(body)

        #expect(batch.videos.count == 1)
        let video = try #require(batch.videos.first)
        #expect(video.id.rawValue == "sm9")
        #expect(video.thumbnailURL?.absoluteString == "https://example.com/hd")
        #expect(video.counts == .init(view: 1, comment: 2, mylist: 3, like: 4))
        #expect(video.ownerName == "中の")
        #expect(video.reasonTag == "音楽")
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveRecommendationTests {
    @Test func guestRecommendations() async throws {
        let batch = try await NicoClient().recommendations(limit: 30)
        #expect(batch.videos.count >= 20)
    }
}
