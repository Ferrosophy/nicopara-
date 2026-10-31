import NicoKit
import Observation

/// The account's あとで見る, loaded in full so a video page can tell whether its video is
/// already in it. Cleared when the login changes.
@MainActor @Observable
final class WatchLaterStore {
    private(set) var items: [WatchLaterItem] = []
    private(set) var totalCount = 0
    private(set) var loaded = false
    private(set) var isLoading = false
    private(set) var error: String?
    private var session: String?

    func contains(_ id: VideoID) -> Bool { items.contains { $0.video.id == id } }

    func loadIfNeeded(_ client: NicoClient) async {
        resetIfLoginChanged(client)
        if !loaded { await reload(client) }
    }

    /// Fetches every page (the site caps あとで見る at a few hundred videos).
    func reload(_ client: NicoClient) async {
        resetIfLoginChanged(client)
        guard client.isLoggedIn, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var all: [WatchLaterItem] = []
            var page = 1
            var total = 0
            while page <= 20 {
                let result = try await client.watchLater(page: page)
                all += result.items
                total = result.totalCount
                guard result.hasNext else { break }
                page += 1
            }
            items = all
            totalCount = total
            loaded = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Adds or removes, then reloads so item IDs match the server.
    func toggle(_ id: VideoID, _ client: NicoClient) async {
        do {
            if let item = items.first(where: { $0.video.id == id }) {
                try await client.removeFromWatchLater(itemIDs: [item.id])
                items.removeAll { $0.id == item.id }
            } else {
                try await client.addToWatchLater(id)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await reload(client)
    }

    func remove(_ toRemove: [WatchLaterItem], _ client: NicoClient) async {
        do {
            try await client.removeFromWatchLater(itemIDs: toRemove.map(\.id))
            let ids = Set(toRemove.map(\.id))
            items.removeAll { ids.contains($0.id) }
            totalCount = max(0, totalCount - toRemove.count)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resetIfLoginChanged(_ client: NicoClient) {
        guard client.userSession != session else { return }
        session = client.userSession
        items = []
        totalCount = 0
        loaded = false
        error = nil
    }
}
