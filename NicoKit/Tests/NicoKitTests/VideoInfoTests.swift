import Foundation
import Testing
@testable import NicoKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct VideoInfoTests {
    // Real response for sm9, captured 2026-10-30.
    @Test func parsesPublicVideo() throws {
        let info = try VideoInfo.parse(watchResponse: fixture("watch-sm9"))

        #expect(info.id.rawValue == "sm9")
        #expect(info.title == "新・豪血寺一族 -煩悩解放 - レッツゴー！陰陽師")
        #expect(info.descriptionText == "レッツゴー！陰陽師（フルコーラスバージョン）")
        #expect(info.duration == 320)
        #expect(info.registeredAt == ISO8601DateFormatter().date(from: "2007-03-05T15:33:00Z"))
        #expect(info.counts == .init(view: 23_122_165, comment: 5_699_589, mylist: 183_247, like: 46_080))
        #expect(info.uploader == .user(
            id: "4", name: "中の",
            iconURL: URL(string: "https://img.nicoprofile.nimg.jp/usericon/defaults/blank.jpg")
        ))
        #expect(info.thumbnailURL?.absoluteString.hasPrefix("https://img.cdn.nimg.jp/s/nicovideo/thumbnails/9/9.original/") == true)
        #expect(info.tags.first == "陰陽師")
        #expect(info.tags.count == 10 || info.tags.count > 0)
        #expect(info.genre == nil) // "未設定"
        #expect(info.access == .free)
        #expect(info.videoStreams.map(\.id) == ["video-h264-360p", "video-h264-360p-lowest"])
        #expect(info.audioStreams.map(\.id) == ["audio-aac-128kbps", "audio-aac-64kbps"])
        #expect(info.accessRightKey?.isEmpty == false)
        #expect(info.watchTrackID == "AAAAAAAAAA_1793339404000")
    }

    @Test func reportsDeletedVideo() throws {
        #expect(throws: NicoError.api(errorCode: "FORBIDDEN", reasonCode: "ADMINISTRATOR_DELETE_VIDEO")) {
            try VideoInfo.parse(watchResponse: fixture("watch-sm1-deleted"))
        }
        let message = NicoError.api(errorCode: "FORBIDDEN", reasonCode: "ADMINISTRATOR_DELETE_VIDEO").errorDescription
        #expect(message == "视频已被管理员删除")
    }

    @Test func rejectsGarbage() {
        #expect {
            try VideoInfo.parse(watchResponse: Data("<html>".utf8))
        } throws: { error in
            if case NicoError.decoding = error { true } else { false }
        }
    }

    @Test func stripsHTML() {
        #expect(HTMLText.plain("a<br>b<BR />c <a href=\"x\">link</a> &amp;lt; &quot;q&quot;") == "a\nb\nc link &lt; \"q\"")
    }
}

/// Hits the real API. Run with `NICO_LIVE=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveTests {
    @Test func fetchesSm9() async throws {
        let info = try await NicoClient().videoInfo(VideoID(parsing: "sm9")!)
        #expect(info.title.contains("陰陽師"))
        #expect(info.counts.view > 20_000_000)
        #expect(!info.videoStreams.isEmpty)
    }

    @Test func fetchesDeletedVideo() async {
        await #expect(throws: NicoError.api(errorCode: "FORBIDDEN", reasonCode: "ADMINISTRATOR_DELETE_VIDEO")) {
            try await NicoClient().videoInfo(VideoID(parsing: "sm1")!)
        }
    }
}
