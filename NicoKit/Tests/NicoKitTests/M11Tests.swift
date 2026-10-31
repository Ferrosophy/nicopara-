import Foundation
import Testing
@testable import NicoKit

@Suite struct TranslateParseTests {
    // Shape of a real `translate_a/t` answer for several texts, captured 2026-10-30.
    @Test func parsesBatch() throws {
        let body = Data(#"[["你要去哪里？","ja"],["88888888","en"],["第一行\n第2行","ja"]]"#.utf8)
        let results = try GoogleTranslator.parse(body)
        #expect(results.map(\.text) == ["你要去哪里？", "88888888", "第一行\n第2行"])
        #expect(results.first?.sourceLanguage == "ja")
    }

    @Test func parsesPlainStrings() throws {
        let results = try GoogleTranslator.parse(Data(#"["只有一个"]"#.utf8))
        #expect(results.map(\.text) == ["只有一个"])
    }

    @Test func rejectsHTML() {
        #expect(throws: NicoError.self) { try GoogleTranslator.parse(Data("<html>Sorry</html>".utf8)) }
    }
}

@Suite struct RankingParseTests {
    @Test func parsesGenres() throws {
        let body = Data("""
        {"meta":{"status":200},"data":{"items":[
          {"featuredKey":"e9uj2uks","label":"総合","isTopLevel":true,"isImmoral":false,"trendTags":[]},
          {"featuredKey":"4eet3ca4","label":"ゲーム","isTopLevel":false,"isImmoral":false,"trendTags":["琴葉茜","FGO"]}
        ]}}
        """.utf8)
        let genres = try RankingGenre.parseList(body)
        #expect(genres.map(\.label) == ["総合", "ゲーム"])
        #expect(genres[1].trendTags == ["琴葉茜", "FGO"])
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveM11Tests {
    @Test func translatesJapanese() async throws {
        let results = try await GoogleTranslator().translate(["どこいくねーん", "88888888"])
        #expect(results.count == 2)
        #expect(results[0].sourceLanguage == "ja")
        #expect(results[0].text != "どこいくねーん")
    }

    @Test func genresAndRanking() async throws {
        let client = NicoClient()
        let genres = try await client.rankingGenres()
        #expect(genres.count >= 20)
        let hasAdultGenre = genres.contains { $0.isImmoral }
        #expect(!hasAdultGenre) // guests don't get the adult genre
        let game = try #require(genres.first { $0.label == "ゲーム" })
        let page = try await client.ranking(game.key, term: .day)
        #expect(page.videos.count >= 50)
        #expect(page.genre == "ゲーム")
        if let tag = game.trendTags.first {
            let tagged = try await client.ranking(game.key, term: .week, tag: tag)
            #expect(tagged.tag == tag)
            #expect(!tagged.videos.isEmpty)
        }
        let second = try await client.ranking(game.key, term: .day, page: 2)
        #expect(Set(second.videos.map(\.id)).isDisjoint(with: page.videos.map(\.id)))
    }

    @Test func suggestsTags() async throws {
        let tags = try await NicoClient().suggestTags("miku")
        #expect(tags.contains("MikuMikuDance"))
    }

    @Test func userVideosSorted() async throws {
        let page = try await NicoClient().userVideos("4", sort: .viewCount, order: .desc, pageSize: 5)
        let views = page.videos.map(\.counts.view)
        #expect(views == views.sorted(by: >))
        let oldest = try await NicoClient().userVideos("4", sort: .registeredAt, order: .asc, pageSize: 1)
        #expect(oldest.videos.first?.id.rawValue == "sm9")
    }
}

@Suite struct M12Tests {
    private func comment(_ id: String, _ vpos: Int, _ body: String, commands: [String] = [], score: Int = 0,
                         fork: String = "main", user: String = "u") -> NicoComment {
        NicoComment(id: id, number: Int(id) ?? 0, vposMs: vpos, body: body, commands: commands, nicoruCount: 0,
                    postedAt: nil, score: score, fork: fork, userID: user)
    }

    @Test func ngLevels() {
        let comments = [comment("1", 0, "a", score: -500), comment("2", 0, "b", score: -2000),
                        comment("3", 0, "c", score: -6000), comment("4", 0, "d", score: -20000)]
        var options = DanmakuFilterOptions()
        options.ngLevel = .none
        #expect(DanmakuFilter.forList(comments, options).count == 4)
        options.ngLevel = .weak
        #expect(DanmakuFilter.forList(comments, options).map(\.id) == ["1", "2", "3"])
        options.ngLevel = .medium
        #expect(DanmakuFilter.forList(comments, options).map(\.id) == ["1", "2"])
        options.ngLevel = .strong
        #expect(DanmakuFilter.forList(comments, options).map(\.id) == ["1"])
    }

    @Test func blocksAndNG() {
        let comments = [comment("1", 0, "普通"), comment("2", 0, "上", commands: ["ue"]),
                        comment("3", 0, "赤", commands: ["red"]), comment("4", 0, "かんたん", fork: "easy"),
                        comment("5", 0, "うp主", fork: "owner"), comment("6", 0, "NGワード入り"),
                        comment("7", 0, "x", user: "bad")]
        var options = DanmakuFilterOptions()
        options.hideFixed = true
        options.hideColored = true
        options.hideEasy = true
        options.hideOwner = true
        options.ng = [NGItem(kind: .word, value: "ngワード"), NGItem(kind: .user, value: "bad")]
        #expect(DanmakuFilter.forOverlay(comments, options).comments.map(\.id) == ["1"])
        // The list ignores the on-screen type blocks (fixed / coloured) but not NG and pools.
        #expect(DanmakuFilter.forList(comments, options).map(\.id) == ["1", "2", "3"])
    }

    @Test func mergesDuplicates() {
        let comments = [comment("1", 0, "888"), comment("2", 1000, "888"), comment("3", 2000, "888"),
                        comment("4", 9000, "888"), comment("5", 9500, "w")]
        var options = DanmakuFilterOptions()
        options.mergeDuplicates = true
        let result = DanmakuFilter.forOverlay(comments, options)
        #expect(result.comments.map(\.id) == ["1", "4", "5"])
        #expect(result.counts == ["1": 3])
        options.countDuplicates = false
        #expect(DanmakuFilter.forOverlay(comments, options).counts.isEmpty)
    }

    @Test func qualitySelection() throws {
        let url = try #require(Bundle.module.url(forResource: "watch-sm9", withExtension: "json", subdirectory: "Fixtures"))
        let info = try VideoInfo.parse(watchResponse: Data(contentsOf: url))
        #expect(HLSPlayback.outputs(for: info, selection: HLSSelection(audioOnly: true)) == [["audio-aac-128kbps"]])
        #expect(HLSPlayback.outputs(for: info, selection: HLSSelection(videoID: "video-h264-360p-lowest", audioID: "audio-aac-64kbps"))
                == [["video-h264-360p-lowest", "audio-aac-64kbps"]])
        // An unknown quality falls back to automatic (all qualities).
        #expect(HLSPlayback.outputs(for: info, selection: HLSSelection(videoID: "video-h264-1080p")).count == 2)
    }

    @Test func parsesNGLeniently() throws {
        let body = Data(#"{"meta":{"status":200},"data":{"items":[{"type":"word","source":"うざい"},{"type":"id","source":"abc"},{"type":"command","source":"big"}]}}"#.utf8)
        #expect(try NGItem.parseList(body) == [NGItem(kind: .word, value: "うざい"), NGItem(kind: .user, value: "abc"),
                                               NGItem(kind: .command, value: "big")])
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveM12Tests {
    @Test func audioOnlyPlayback() async throws {
        let client = NicoClient()
        let info = try await client.videoInfo(VideoID(parsing: "sm9")!)
        let playback = try await client.hlsPlayback(for: info, selection: HLSSelection(audioOnly: true))
        #expect(playback.cookies.contains { $0.name == "domand_bid" })
    }

    @Test func guestHasNoNG() async {
        await #expect { try await NicoClient().ngSettings() } throws: { ($0 as? NicoError)?.isUnauthorized == true }
    }
}
