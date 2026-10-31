import Foundation
import NicoKit
import Observation

/// Translations of texts (descriptions, danmaku), cached by language and text for the whole
/// app session, so the same danmaku ("888" …) or a revisited video is never sent twice.
@MainActor @Observable
final class TranslationStore {
    private(set) var cache: [String: String] = [:]
    private(set) var lastError: String?
    @ObservationIgnored private var inFlight: Set<String> = []

    private func key(_ text: String, _ target: String) -> String { "\(target)\u{1F}\(text)" }

    /// The cached translation, or nil if not translated yet. Nil also when the translation is
    /// the same as the original (already in the target language), so callers show nothing.
    func translation(of text: String, to target: String) -> String? {
        guard let result = cache[key(text, target)], result != text else { return nil }
        return result
    }

    func isTranslated(_ text: String, to target: String) -> Bool { cache[key(text, target)] != nil }

    /// Fetches whatever of `texts` is neither cached nor already being fetched.
    func request(_ texts: [String], to target: String) async {
        var seen = Set<String>()
        let missing = texts.filter { text in
            let k = key(text, target)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  cache[k] == nil, !inFlight.contains(k), seen.insert(k).inserted else { return false }
            return true
        }
        guard !missing.isEmpty else { return }
        missing.forEach { inFlight.insert(key($0, target)) }
        defer { missing.forEach { inFlight.remove(key($0, target)) } }
        do {
            let results = try await GoogleTranslator(target: target).translate(missing).map(\.text)
            for (text, result) in zip(missing, results) { cache[key(text, target)] = result }
            lastError = nil
        } catch {
            lastError = String(localized: "翻译失败：\(error.localizedDescription)")
        }
    }

    func clear() {
        cache = [:]
    }
}
