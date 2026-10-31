import CryptoKit
import Foundation
import NicoKit
import Observation

/// The recommendation feed, kept for the life of the app and saved to disk, so it only
/// changes when the user pulls to refresh (or logs in / out, which is a different feed).
/// Switching tabs, opening a video and coming back, or relaunching the app keep it as is.
@MainActor @Observable
final class FeedStore {
    private(set) var videos: [VideoSummary] = []
    private(set) var isLoadingMore = false
    private(set) var reachedEnd = false
    private(set) var error: String?

    private var seen: Set<VideoID> = []
    /// Which login the feed belongs to (a hash of the session cookie, never the cookie itself).
    private var owner: String?
    private var restored = false

    private struct Saved: Codable {
        var owner: String
        var videos: [VideoSummary]
        var reachedEnd: Bool
    }

    private static let fileURL = URL.applicationSupportDirectory.appending(path: "feed.json")

    /// Shows the saved feed if there is one for this login; fetches only when there is none.
    func loadIfNeeded(_ client: NicoClient) async {
        let key = Self.owner(of: client)
        if !restored {
            restored = true
            restore(for: key)
        }
        guard owner != key || videos.isEmpty else { return }
        await refresh(client)
    }

    /// Replaces the feed with a new batch. The current list stays visible until it arrives.
    func refresh(_ client: NicoClient) async {
        do {
            let batch = try await client.recommendations()
            videos = batch.videos
            seen = Set(batch.videos.map(\.id))
            owner = Self.owner(of: client)
            reachedEnd = false
            error = nil
            save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Appends another batch, skipping videos already in the feed.
    func loadMore(_ client: NicoClient) async {
        guard !isLoadingMore, !reachedEnd, !videos.isEmpty, owner == Self.owner(of: client) else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let fresh = try await client.recommendations().videos.filter { !seen.contains($0.id) }
            if fresh.isEmpty {
                reachedEnd = true
            } else {
                videos += fresh
                seen.formUnion(fresh.map(\.id))
            }
            error = nil
            save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restore(for key: String) {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.owner == key else { return }
        videos = saved.videos
        seen = Set(saved.videos.map(\.id))
        reachedEnd = saved.reachedEnd
        owner = saved.owner
    }

    private func save() {
        guard let owner else { return }
        do {
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(Saved(owner: owner, videos: videos, reachedEnd: reachedEnd))
                .write(to: Self.fileURL, options: .atomic)
        } catch {
            // A cache only: losing it means one extra fetch on next launch.
        }
    }

    private static func owner(of client: NicoClient) -> String {
        guard let session = client.userSession else { return "guest" }
        return SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
