import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NicoKit

@Suite struct HLSPlaybackTests {
    private func sm9() throws -> VideoInfo {
        let url = try #require(Bundle.module.url(forResource: "watch-sm9", withExtension: "json", subdirectory: "Fixtures"))
        return try VideoInfo.parse(watchResponse: Data(contentsOf: url))
    }

    @Test func pairsEveryVideoWithBestAudio() throws {
        #expect(HLSPlayback.outputs(for: try sm9()) == [
            ["video-h264-360p", "audio-aac-128kbps"],
            ["video-h264-360p-lowest", "audio-aac-128kbps"],
        ])
    }

    @Test func noOutputsWithoutAudio() throws {
        var info = try sm9()
        info.audioStreams = []
        #expect(HLSPlayback.outputs(for: info).isEmpty)
    }

    // Shape of a real response (201 + Set-Cookie domand_bid), captured 2026-10-30; values shortened.
    @Test func parsesAccessRights() throws {
        let body = Data("""
        {"meta":{"status":201},"data":{"contentUrl":"https://delivery.domand.nicovideo.jp/hlsbid/abc/playlists/variants/def.m3u8?session=xyz"}}
        """.utf8)
        let url = URL(string: "https://nvapi.nicovideo.jp/v1/watch/sm9/access-rights/hls")!
        let headers = [
            "Set-Cookie": "domand_bid=secret123; expires=Wed, 04 Nov 2026 06:02:55 GMT; Max-Age=86400; path=/; domain=nicovideo.jp; priority=Low; secure; HttpOnly",
        ]

        let playback = try HLSPlayback.parse(accessRightsResponse: body, headers: headers, url: url)

        #expect(playback.url.host == "delivery.domand.nicovideo.jp")
        #expect(playback.cookies.map(\.name) == ["domand_bid"])
        #expect(playback.cookies.first?.value == "secret123")
        #expect(playback.cookies.first?.domain.hasSuffix("nicovideo.jp") == true)
        #expect(playback.httpCookies.count == 1)
    }

    @Test func reportsAccessRightsError() {
        let body = Data(#"{"meta":{"status":403,"errorCode":"FORBIDDEN"}}"#.utf8)
        let url = URL(string: "https://nvapi.nicovideo.jp/")!
        #expect(throws: NicoError.api(errorCode: "FORBIDDEN", reasonCode: nil)) {
            try HLSPlayback.parse(accessRightsResponse: body, headers: [:], url: url)
        }
    }
}

/// Hits the real API. Run with `NICO_LIVE=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveHLSTests {
    /// Walks the chain a player follows (master → media playlist → AES key → segment), and
    /// checks that the cookie is what unlocks the master playlist and the key.
    @Test func sm9PlaybackChain() async throws {
        let client = NicoClient()
        let info = try await client.videoInfo(VideoID(parsing: "sm9")!)
        let playback = try await client.hlsPlayback(for: info)
        #expect(playback.cookies.contains { $0.name == "domand_bid" })

        // A session that never stores cookies, so only what we pass explicitly is sent.
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let bare = URLSession(configuration: config)
        func get(_ url: URL, cookies: Bool = true) async throws -> (Data, Int) {
            var request = URLRequest(url: url)
            if cookies {
                HTTPCookie.requestHeaderFields(with: playback.httpCookies).forEach {
                    request.setValue($0.value, forHTTPHeaderField: $0.key)
                }
            }
            let (data, response) = try await bare.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        #expect(try await get(playback.url, cookies: false).1 == 403)
        let master = String(decoding: try await get(playback.url).0, as: UTF8.self)
        #expect(master.hasPrefix("#EXTM3U"))

        let mediaURL = try #require(master.split(separator: "\n").first { $0.hasPrefix("https://") })
        let media = String(decoding: try await get(URL(string: String(mediaURL))!).0, as: UTF8.self)
        let keyLine = try #require(media.split(separator: "\n").first { $0.hasPrefix("#EXT-X-KEY") })
        #expect(keyLine.contains("METHOD=AES-128"))
        let keyURI = try #require(keyLine.firstMatch(of: /URI="([^"]+)"/)?.output.1)
        let keyURL = URL(string: String(keyURI))!

        #expect(try await get(keyURL, cookies: false).1 == 403)
        let (key, keyStatus) = try await get(keyURL)
        #expect(keyStatus == 200)
        #expect(key.count == 16)

        let segment = try #require(media.split(separator: "\n").first { $0.hasPrefix("https://") })
        let (bytes, segmentStatus) = try await get(URL(string: String(segment))!)
        #expect(segmentStatus == 200)
        #expect(bytes.count > 10_000)
    }
}
