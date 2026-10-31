import Foundation
import Testing
@testable import NicoKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

// Fixtures are real responses captured 2026-10-30 (public user 4, uploader 46251515).
@Suite struct FollowTests {
    @Test func parsesFollowingPage() throws {
        let page = try FollowingPage.parse(fixture("following-user4"))
        // Asked for 3, the site sent 2: pages can come back short (hidden users are left out),
        // so paging must follow the cursor, not the item count.
        #expect(page.users.count == 2)
        #expect(page.users.first?.id == "39040725")
        #expect(page.users.first?.nickname == "インコさん")
        #expect(page.users.first?.iconURL != nil)
        #expect(page.totalCount == 90)
        #expect(page.nextCursor == "20161020164724_98587")
    }

    @Test func lastFollowingPageHasNoCursor() throws {
        let body = Data(#"{"meta":{"status":200},"data":{"items":[],"summary":{"followees":0,"hasNext":false,"cursor":"cursorEnd"}}}"#.utf8)
        #expect(try FollowingPage.parse(body).nextCursor == nil)
    }

    @Test func parsesFeed() throws {
        let page = try FollowFeedPage.parse(fixture("activities-user"))
        #expect(page.uploads.count == 3)
        let first = try #require(page.uploads.first)
        #expect(first.videoID.rawValue == "sm46980459")
        #expect(first.title == "ゆかりわんこの大発掘！　その２【超大発掘】")
        #expect(first.duration == 428)
        #expect(first.uploaderName == "もがが")
        #expect(first.uploaderType == "user")
        #expect(first.postedAt != nil)
        #expect(page.nextCursor?.isEmpty == false)
    }

    @Test func feedNeedsLogin() throws {
        #expect {
            try FollowFeedPage.parse(fixture("activities-unauthorized"))
        } throws: { error in
            (error as? NicoError)?.isUnauthorized == true
        }
    }

    @Test func parsesUserVideos() throws {
        let page = try UserVideosPage.parse(fixture("user-videos-4"), page: 1, pageSize: 2)
        #expect(page.videos.count == 2)
        #expect(page.videos.first?.id.rawValue == "sm18219289")
        #expect(page.totalCount == 19)
        #expect(page.canLoadMore)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveFollowTests {
    /// The site lists follows newest first: each page's cursor (a follow time) is older.
    @Test func followingIsNewestFirst() async throws {
        let client = NicoClient()
        let first = try await client.following(of: "4", pageSize: 30)
        let second = try await client.following(of: "4", cursor: first.nextCursor, pageSize: 30)
        let c1 = try #require(first.nextCursor), c2 = try #require(second.nextCursor)
        #expect(c1 > c2)
        #expect(Set(first.users.map(\.id)).isDisjoint(with: second.users.map(\.id)))
    }

    @Test func guestCannotReadOwnFollows() async {
        await #expect { try await NicoClient().following() } throws: { ($0 as? NicoError)?.isUnauthorized == true }
        await #expect { try await NicoClient().followFeed() } throws: { ($0 as? NicoError)?.isUnauthorized == true }
    }

    @Test func userVideosNewestFirst() async throws {
        let page = try await NicoClient().userVideos("4", pageSize: 10)
        let dates = page.videos.compactMap(\.registeredAt)
        #expect(!dates.isEmpty)
        #expect(dates == dates.sorted(by: >))
    }
}
