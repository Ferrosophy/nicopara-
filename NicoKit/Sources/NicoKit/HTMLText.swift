import Foundation

/// Minimal HTML-to-text for video descriptions. Foundation's HTML importer is not
/// available on Linux, and descriptions only use a few simple tags.
enum HTMLText {
    static func plain(_ html: String) -> String {
        var text = html.replacing(/<br\s*\/?>/.ignoresCase(), with: "\n")
        text = text.replacing(/<[^>]+>/, with: "")
        let entities = [
            "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        ]
        for (entity, character) in entities {
            text = text.replacing(entity, with: character)
        }
        // Last, so "&amp;lt;" becomes "&lt;" and not "<".
        text = text.replacing("&amp;", with: "&")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
