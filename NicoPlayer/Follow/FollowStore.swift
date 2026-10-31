import NicoKit
import Observation

/// 关注 data for the app's lifetime, so switching 更新列表 / 关注列表 or tabs keeps the lists
/// and scroll position. Cleared when the login changes. Both lists refresh on pull.
@MainActor @Observable
final class FollowStore {
    struct Paged<Item> {
        var items: [Item] = []
        var cursor: String?
        var loaded = false
        var isLoading = false
        var error: String?

        var canLoadMore: Bool { loaded && cursor != nil }
    }

    private(set) var uploads = Paged<FollowUpload>()
    private(set) var following = Paged<NicoUser>()
    private var session: String?

    // MARK: 更新列表

    func loadUploadsIfNeeded(_ client: NicoClient) async {
        resetIfLoginChanged(client)
        if !uploads.loaded { await refreshUploads(client) }
    }

    func refreshUploads(_ client: NicoClient) async {
        await load(\.uploads, reset: true) { try await client.followFeed().pair }
    }

    func loadMoreUploads(_ client: NicoClient) async {
        guard uploads.canLoadMore else { return }
        let cursor = uploads.cursor
        await load(\.uploads, reset: false) { try await client.followFeed(cursor: cursor).pair }
    }

    // MARK: 关注列表

    func loadFollowingIfNeeded(_ client: NicoClient) async {
        resetIfLoginChanged(client)
        if !following.loaded { await refreshFollowing(client) }
    }

    func refreshFollowing(_ client: NicoClient) async {
        await load(\.following, reset: true) { try await client.following().pair }
    }

    func loadMoreFollowing(_ client: NicoClient) async {
        guard following.canLoadMore else { return }
        let cursor = following.cursor
        await load(\.following, reset: false) { try await client.following(cursor: cursor).pair }
    }

    /// After 关注 / 取消关注 elsewhere (video page, 听视频): the list is newest first, so a new
    /// follow goes on top; 更新列表 reloads the next time it's shown.
    func followChanged(_ user: NicoUser, isFollowing: Bool) {
        following.items.removeAll { $0.id == user.id }
        if isFollowing, following.loaded { following.items.insert(user, at: 0) }
        uploads.loaded = false
    }

    // MARK: -

    private func resetIfLoginChanged(_ client: NicoClient) {
        guard client.userSession != session else { return }
        session = client.userSession
        uploads = Paged()
        following = Paged()
    }

    private func load<Item: Identifiable>(
        _ list: ReferenceWritableKeyPath<FollowStore, Paged<Item>>, reset: Bool,
        _ fetch: () async throws -> ([Item], String?)
    ) async {
        guard !self[keyPath: list].isLoading else { return }
        self[keyPath: list].isLoading = true
        defer { self[keyPath: list].isLoading = false }
        do {
            let (items, cursor) = try await fetch()
            if reset {
                self[keyPath: list].items = items
            } else {
                let known = Set(self[keyPath: list].items.map(\.id))
                self[keyPath: list].items += items.filter { !known.contains($0.id) }
            }
            self[keyPath: list].cursor = cursor
            self[keyPath: list].loaded = true
            self[keyPath: list].error = nil
        } catch {
            self[keyPath: list].error = error.localizedDescription
        }
    }
}

private extension FollowFeedPage {
    var pair: ([FollowUpload], String?) { (uploads, nextCursor) }
}

private extension FollowingPage {
    var pair: ([NicoUser], String?) { (users, nextCursor) }
}
