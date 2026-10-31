import Foundation
import Testing
@testable import NicoKit

/// The essential video object as nvapi sends it in lists.
private let essential = """
{"type":"essential","id":"sm9","title":"t","registeredAt":"2007-03-06T00:33:00+09:00",
 "count":{"view":1,"comment":2,"mylist":3,"like":4},"thumbnail":{"url":"https://example.com/a"},
 "duration":320,"owner":{"name":"中の","iconUrl":"https://example.com/i"}}
"""

@Suite struct MyListsTests {
    // Field names follow the site's decoder for あとで見る (itemId, watchId, memo, addedAt, status, video).
    @Test func parsesWatchLater() throws {
        let body = Data("""
        {"meta":{"status":200},"data":{"watchLater":{"items":[
          {"itemId":1234,"watchId":"sm9","memo":"","addedAt":"2026-10-30T12:00:00+09:00","status":"public","video":\(essential)},
          {"itemId":5678,"watchId":"sm1","memo":"m","addedAt":"2026-10-29T12:00:00+09:00","status":"deleted"}
        ],"totalCount":2,"hasNext":false,"hasInvisibleItems":false}}}
        """.utf8)
        let page = try WatchLaterPage.parse(body, page: 1)

        // The deleted video has no `video` object and is skipped.
        #expect(page.items.count == 1)
        let item = try #require(page.items.first)
        #expect(item.id == "1234")
        #expect(item.video.id.rawValue == "sm9")
        #expect(item.memo == nil)
        #expect(item.addedAt != nil)
        #expect(page.totalCount == 2)
        #expect(!page.hasNext)
    }

    @Test func parsesHistory() throws {
        let body = Data("""
        {"meta":{"status":200},"data":{"items":[
          {"watchId":"sm9","lastViewedAt":"2026-10-30T12:00:00+09:00","views":3,"video":\(essential)}
        ],"nextCursor":"abc","hasNext":true}}
        """.utf8)
        let page = try HistoryPage.parse(body)
        #expect(page.items.map(\.video.id.rawValue) == ["sm9"])
        #expect(page.items.first?.views == 3)
        #expect(page.items.first?.lastViewedAt != nil)
        #expect(page.nextCursor == "abc")
    }

    /// If the real shape differs, the error carries the raw body so a device report shows it.
    @Test func unreadableHistoryShowsBody() {
        let body = Data(#"{"meta":{"status":200},"data":{"items":[{"content":{"id":"sm9"}}]}}"#.utf8)
        #expect {
            try HistoryPage.parse(body)
        } throws: { error in
            guard case NicoError.decoding(let detail) = error else { return false }
            return detail.contains(#""content""#)
        }
    }

    @Test func emptyHistory() throws {
        let page = try HistoryPage.parse(Data(#"{"meta":{"status":200},"data":{"items":[],"hasNext":false}}"#.utf8))
        #expect(page.items.isEmpty)
        #expect(page.nextCursor == nil)
    }

    @Test func infoToSummary() throws {
        let url = try #require(Bundle.module.url(forResource: "watch-sm9", withExtension: "json", subdirectory: "Fixtures"))
        let info = try VideoInfo.parse(watchResponse: Data(contentsOf: url))
        let summary = info.summary
        #expect(summary.id == info.id)
        #expect(summary.title == info.title)
        #expect(summary.ownerName == "中の")
        #expect(!summary.isPaymentRequired)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveMyListsTests {
    private func isUnauthorized(_ error: any Error) -> Bool { (error as? NicoError)?.isUnauthorized == true }

    @Test func guestHasNoAccountLists() async {
        let client = NicoClient()
        await #expect { try await client.watchLater() } throws: { isUnauthorized($0) }
        await #expect { try await client.addToWatchLater(VideoID(parsing: "sm9")!) } throws: { isUnauthorized($0) }
        await #expect { try await client.removeFromWatchLater(itemIDs: ["1"]) } throws: { isUnauthorized($0) }
        await #expect { try await client.watchHistory() } throws: { isUnauthorized($0) }
    }

    /// The playback report is accepted (the site sends it for guests too).
    @Test func playbackReportAccepted() async throws {
        let client = NicoClient()
        let info = try await client.videoInfo(VideoID(parsing: "sm9")!)
        try await client.reportPlayback(of: info)
    }
}
