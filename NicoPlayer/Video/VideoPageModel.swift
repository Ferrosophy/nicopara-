import NicoKit
import Observation

/// Everything one video page shows, loaded once and kept while the page is on the stack
/// (so going back to it finds the player paused where it was).
@MainActor @Observable
final class VideoPageModel {
    let id: VideoID

    private(set) var info: VideoInfo?
    private(set) var loadError: String?

    private(set) var player: PlayerModel?
    /// Long-press speed for the player (应用设置).
    var boostRate: Float = 2 {
        didSet { player?.boostRate = boostRate }
    }
    /// 循环播放 (应用设置 / ⚙ menu).
    var loops = false {
        didSet { player?.loops = loops }
    }
    /// The quality being played (画质 / 音质); nil IDs mean 自动.
    private(set) var selection = HLSSelection.automatic
    /// Goes up each time the video plays to its end (not when looping), for 自动播放下一个.
    private(set) var endedCount = 0
    /// The account's NG list (when 同步账号屏蔽设置 is on and logged in).
    private(set) var ngItems: [NGItem] = []
    private(set) var isStarting = false
    private(set) var playError: String?

    private(set) var comments: [NicoComment] = []
    private(set) var commentsLoaded = false
    private(set) var commentsError: String?

    private(set) var related: [VideoSummary] = []
    private(set) var profile: UserProfile?
    private(set) var uploadCount: Int?
    private(set) var series: SeriesPosition?

    private(set) var isLiked = false
    private(set) var likeCount = 0
    /// nil when not known (guests, or the watch data didn't say).
    private(set) var isFollowing: Bool?
    private(set) var actionError: String?
    /// The login the watch data was loaded with; reload when it changes.
    private var loadedSession: String?
    private var hasLoaded = false

    init(id: VideoID) {
        self.id = id
    }

    /// Loads the watch data (again if the login changed), starts playback once, and fills in
    /// comments, related videos, uploader numbers and the series alongside.
    func load(_ client: NicoClient, autoplay: Bool = true,
              selection: (VideoInfo) -> HLSSelection = { _ in .automatic }, loadNG: Bool = false) async {
        guard !hasLoaded || loadedSession != client.userSession else { return }
        hasLoaded = true
        loadedSession = client.userSession
        do {
            let info = try await client.videoInfo(id)
            self.info = info
            loadError = nil
            isLiked = info.isLiked ?? false
            likeCount = info.counts.like
            isFollowing = info.isFollowingUploader
        } catch {
            loadError = error.localizedDescription
            hasLoaded = false
            return
        }
        guard let info else { return }

        if player == nil {
            self.selection = selection(info)
            if autoplay { await startPlayback(client) }
        }

        if loadNG, client.isLoggedIn {
            ngItems = (try? await client.ngSettings()) ?? []
        }
        async let comments: Void = loadComments(client, info)
        async let related: Void = loadRelated(client)
        async let uploader: Void = loadUploader(client, info)
        async let series: Void = loadSeries(client, info)
        _ = await (comments, related, uploader, series)
    }

    func startPlayback(_ client: NicoClient) async {
        guard let info, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let playback = try await client.hlsPlayback(for: info, selection: selection)
            let model = PlayerModel(fallbackDuration: info.duration)
            model.boostRate = boostRate
            model.loops = loops
            model.onEnded = { [weak self] in self?.endedCount += 1 }
            model.load(playback.url, cookies: playback.httpCookies, startAt: PlaybackHandoff.take(for: id) ?? 0)
            player = model
            playError = nil
            // As the site's player does: count the view and add it to the account's history.
            try? await client.reportPlayback(of: info)
        } catch {
            playError = error.localizedDescription
        }
    }

    /// 画质 / 音质: asks Niconico for a playlist with just that quality (nil = 自动, all of them)
    /// and continues from the same moment.
    func switchQuality(_ client: NicoClient, videoID: String?, audioID: String?) async {
        guard let info, let player else { return }
        let newSelection = HLSSelection(videoID: videoID, audioID: audioID)
        guard newSelection != selection else { return }
        let position = player.currentTime
        let wasPlaying = player.isPlaying
        do {
            let playback = try await client.hlsPlayback(for: info, selection: newSelection)
            selection = newSelection
            player.load(playback.url, cookies: playback.httpCookies, startAt: position, autoplay: wasPlaying)
        } catch {
            playError = error.localizedDescription
        }
    }

    /// The video to play after this one: the next in its series if known, else the first
    /// related video.
    func nextVideo(_ client: NicoClient) async -> VideoID? {
        if let series, let order = series.order {
            let pageSize = 100
            let page = (order) / pageSize + 1 // the page holding order + 1
            if let result = try? await client.series(series.series.id, page: page, pageSize: pageSize),
               let next = result.entries.first(where: { $0.order == order + 1 }) {
                return next.video.id
            }
        }
        return related.first?.id
    }

    /// いいね, synced with the account. Updates at once and rolls back if the call fails.
    func toggleLike(_ client: NicoClient) async {
        let liked = !isLiked
        isLiked = liked
        likeCount += liked ? 1 : -1
        do {
            try await client.setLiked(liked, video: id)
            actionError = nil
        } catch {
            isLiked = !liked
            likeCount += liked ? -1 : 1
            actionError = String(localized: "点赞失败：\(error.localizedDescription)")
        }
    }

    /// 关注 / 取消关注 the uploader, synced with the account. Returns the new state on success.
    @discardableResult
    func toggleFollow(_ client: NicoClient) async -> Bool? {
        guard case .user(let userID, _, _) = info?.uploader else { return nil }
        let following = !(isFollowing ?? false)
        isFollowing = following
        do {
            try await client.setFollowing(following, user: userID)
            if let profile { self.profile?.followerCount = max(0, profile.followerCount + (following ? 1 : -1)) }
            actionError = nil
            return following
        } catch {
            isFollowing = !following
            actionError = String(localized: "关注失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func loadComments(_ client: NicoClient, _ info: VideoInfo) async {
        do {
            comments = try await client.comments(for: info)
            commentsError = nil
        } catch {
            commentsError = String(localized: "弹幕加载失败：\(error.localizedDescription)")
        }
        commentsLoaded = true
    }

    private func loadRelated(_ client: NicoClient) async {
        related = (try? await client.relatedVideos(to: id)) ?? []
    }

    private func loadUploader(_ client: NicoClient, _ info: VideoInfo) async {
        guard case .user(let userID, _, _) = info.uploader else { return }
        async let profile = try? client.userProfile(userID)
        async let uploads = try? client.userVideos(userID, pageSize: 1)
        self.profile = await profile
        // The user API's own answer is the reliable one; the watch data sometimes lacks it.
        if let following = self.profile?.isFollowing { isFollowing = following }
        uploadCount = await uploads?.totalCount
    }

    private func loadSeries(_ client: NicoClient, _ info: VideoInfo) async {
        series = try? await client.seriesPosition(of: info)
    }
}
