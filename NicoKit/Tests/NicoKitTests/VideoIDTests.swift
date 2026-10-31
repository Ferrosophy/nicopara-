import Testing
import NicoKit

@Suite struct VideoIDTests {
    @Test(arguments: [
        ("sm9", "sm9"),
        ("so38016254", "so38016254"),
        ("nm2829323", "nm2829323"),
        ("https://www.nicovideo.jp/watch/sm9", "sm9"),
        ("https://sp.nicovideo.jp/watch/sm9?ref=share", "sm9"),
        ("https://nico.ms/sm9", "sm9"),
        ("  看这个 https://www.nicovideo.jp/watch/sm45000000  ", "sm45000000"),
    ])
    func parses(input: String, expected: String) {
        #expect(VideoID(parsing: input)?.rawValue == expected)
    }

    @Test(arguments: ["", "hello", "sm", "https://www.nicovideo.jp/", "xsm9"])
    func rejects(input: String) {
        #expect(VideoID(parsing: input) == nil)
    }

    @Test func watchURL() {
        #expect(VideoID(parsing: "sm9")?.watchURL == "https://www.nicovideo.jp/watch/sm9")
    }
}
