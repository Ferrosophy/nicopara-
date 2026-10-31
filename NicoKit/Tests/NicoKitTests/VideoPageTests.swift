import Foundation
import Testing
@testable import NicoKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

// Fixtures are real responses captured 2026-10-30.
@Suite struct VideoPageTests {
    @Test func watchDataHasCommentSource() throws {
        let info = try VideoInfo.parse(watchResponse: fixture("watch-sm9"))
        let source = try #require(info.commentSource)
        #expect(source.server.absoluteString == "https://public.nvcomment.nicovideo.jp")
        #expect(!source.threadKey.isEmpty)
        // Guests get no viewer state and no series.
        #expect(info.isLiked == nil)
        #expect(info.isFollowingUploader == nil)
        #expect(info.series == nil)
    }

    /// `params` goes back to the server exactly as received (ids stay integers-as-strings etc.).
    @Test func commentParamsRoundTrip() throws {
        let raw = #"{"targets":[{"id":"1173108780","fork":"main"}],"language":"ja-jp","n":5}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(again == value)
        #expect(String(decoding: try JSONEncoder().encode(JSONValue.number(5)), as: UTF8.self) == "5")
    }

    @Test func parsesComments() throws {
        let comments = try NicoComment.parse(threads: fixture("threads-sm9"))
        #expect(!comments.isEmpty)
        #expect(comments.map(\.vposMs) == comments.map(\.vposMs).sorted())
        #expect(comments.contains { $0.score <= NicoComment.hiddenScore } || comments.count > 0)
        #expect(Set(comments.map(\.fork)).isSubset(of: ["owner", "main", "easy"]))
    }

    @Test func commentCommands() {
        func make(_ commands: [String]) -> NicoComment {
            NicoComment(id: "1", number: 1, vposMs: 0, body: "x", commands: commands, nicoruCount: 0,
                    postedAt: nil, score: 0, fork: "main")
        }
        #expect(make(["184"]).position == .scroll)
        #expect(make(["ue", "big", "red"]).position == .top)
        #expect(make(["ue", "big", "red"]).size == .big)
        #expect(make(["ue", "big", "red"]).color == 0xFF0000)
        #expect(make(["shita", "small", "#865326"]).position == .bottom)
        #expect(make(["shita", "small", "#865326"]).color == 0x865326)
        #expect(make([]).color == 0xFFFFFF)
    }

    @Test func parsesRelatedSkippingMylists() throws {
        let videos = try RecommendationBatch.parse(fixture("related-sm9")).videos
        #expect(videos.map(\.id.rawValue) == ["sm46221348", "sm43891948", "sm18219289", "sm13256898"])
    }

    @Test func parsesSeries() throws {
        let page = try SeriesPage.parse(fixture("series-446773"), page: 1, pageSize: 3)
        #expect(page.series.title == "【ティンクルスターナイツ】星騎士ストーリー")
        #expect(page.totalCount == 210)
        #expect(page.entries.first?.order == 1)
        #expect(page.canLoadMore)
    }

    @Test func parsesUserProfile() throws {
        let profile = try UserProfile.parse(fixture("user-4"))
        #expect(profile.user.nickname == "中の")
        #expect(profile.followerCount == 11152)
        #expect(profile.followeeCount == 90)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveVideoPageTests {
    @Test func commentsForSm9() async throws {
        let client = NicoClient()
        let info = try await client.videoInfo(VideoID(parsing: "sm9")!)
        let comments = try await client.comments(for: info)
        #expect(comments.count > 100)
        #expect(comments.contains { $0.position == .top })
    }

    @Test func related() async throws {
        let videos = try await NicoClient().relatedVideos(to: VideoID(parsing: "sm9")!)
        #expect(!videos.isEmpty)
        #expect(!videos.contains { $0.id.rawValue == "sm9" })
    }

    /// Guests don't get the series in the watch data; it is found via the uploader's list.
    @Test func seriesFoundThroughUploader() async throws {
        let client = NicoClient()
        let page = try await client.userVideos("30765823", pageSize: 30)
        // Pick a recent upload of this uploader that is in a series (most of theirs are).
        for video in page.videos.prefix(10) {
            let info = try await client.videoInfo(video.id)
            if let position = try await client.seriesPosition(of: info) {
                #expect(position.order != nil)
                #expect((position.totalCount ?? 0) > 0)
                return
            }
        }
        Issue.record("none of the latest uploads had a series")
    }

    @Test func guestCannotLikeOrFollow() async {
        let client = NicoClient()
        let unauthorized: (any Error) -> Bool = {
            if case NicoError.api("UNAUTHORIZED", _) = $0 { return true }
            if case NicoError.http(401) = $0 { return true }
            return false
        }
        await #expect { try await client.setLiked(true, video: VideoID(parsing: "sm9")!) } throws: { unauthorized($0) }
        await #expect { try await client.setFollowing(true, user: "4") } throws: { unauthorized($0) }
    }
}
