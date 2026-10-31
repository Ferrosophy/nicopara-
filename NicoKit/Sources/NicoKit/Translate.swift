import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Google Translate's free web endpoint (no API key). Unofficial: it may rate-limit or change.
/// `translate_a/t` takes many `q` values in one POST and answers one result per text, in order.
public struct GoogleTranslator: Sendable {
    public static let endpoint = URL(string: "https://translate.googleapis.com/translate_a/t")!
    /// Texts per request; the endpoint also limits the total size, so keep batches modest.
    public static let batchSize = 40

    public var target: String
    private let session: URLSession

    public init(target: String = "zh-CN", session: URLSession = NicoClient.sharedSession) {
        self.target = target
        self.session = session
    }

    /// Translates `texts` (in batches), returning results in the same order.
    public func translate(_ texts: [String]) async throws -> [Translation] {
        var results: [Translation] = []
        for start in stride(from: 0, to: texts.count, by: Self.batchSize) {
            let batch = Array(texts[start..<min(start + Self.batchSize, texts.count)])
            results += try await translateBatch(batch)
        }
        return results
    }

    private func translateBatch(_ texts: [String]) async throws -> [Translation] {
        guard !texts.isEmpty else { return [] }
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client", value: "gtx"), .init(name: "sl", value: "auto"), .init(name: "tl", value: target),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = texts.map { URLQueryItem(name: "q", value: $0) }
        // URLComponents leaves "+" unescaped, which a form body would read as a space.
        let body = (form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        request.httpBody = Data(body.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NicoError.network(error.localizedDescription)
        }
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw NicoError.http(status: status)
        }
        let results = try Self.parse(data)
        guard results.count == texts.count else {
            throw NicoError.decoding("翻译结果数量不对（\(results.count)/\(texts.count)）")
        }
        return results
    }

    /// Each item is `["译文", "ja"]`, or just `"译文"` in some responses.
    static func parse(_ data: Data) throws -> [Translation] {
        let items: [JSONValue]
        do {
            items = try JSONDecoder().decode([JSONValue].self, from: data)
        } catch {
            throw NicoError.decoding("翻译返回的不是预期格式：\(String(decoding: data.prefix(120), as: UTF8.self))")
        }
        return try items.map { item in
            switch item {
            case .string(let text):
                return Translation(text: text, sourceLanguage: nil)
            case .array(let parts):
                guard case .string(let text) = parts.first else { throw NicoError.decoding("翻译结果缺少译文") }
                if parts.count > 1, case .string(let language) = parts[1] {
                    return Translation(text: text, sourceLanguage: language)
                }
                return Translation(text: text, sourceLanguage: nil)
            default:
                throw NicoError.decoding("翻译结果格式不认识")
            }
        }
    }
}

public struct Translation: Sendable, Equatable {
    public var text: String
    /// Detected language of the original, e.g. "ja".
    public var sourceLanguage: String?
}
