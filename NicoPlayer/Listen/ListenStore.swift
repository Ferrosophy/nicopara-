import AVFoundation
import MediaPlayer
import NicoKit
import Observation
import UIKit

/// 听视频: plays a list of videos as audio only (Niconico serves an audio-only playlist), in
/// the background, with lock-screen / Control Center controls. One per app.
@MainActor @Observable
final class ListenStore {
    enum Mode: CaseIterable {
        case loopAll, loopOne, shuffle

        var symbol: String {
            switch self {
            case .loopAll: "repeat"
            case .loopOne: "repeat.1"
            case .shuffle: "shuffle"
            }
        }

        var label: String {
            switch self {
            case .loopAll: L("列表循环")
            case .loopOne: L("单曲循环")
            case .shuffle: L("随机播放")
            }
        }
    }

    // MARK: Queue
    private(set) var queue: [VideoSummary] = []
    /// Name of the list being played (shown at the top of the page).
    private(set) var sourceTitle = ""
    private(set) var index: Int?
    var mode: Mode = .loopAll {
        didSet { rebuildOrder() }
    }
    /// The page is open (full screen); closing it keeps playing, with a small bar to come back.
    var isPresented = false

    // MARK: Now playing
    private(set) var info: VideoInfo?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var error: String?
    private(set) var isLiked = false
    private(set) var likeCount = 0
    private(set) var isFollowing: Bool?
    var isScrubbing = false

    var current: VideoSummary? { index.flatMap { queue.indices.contains($0) ? queue[$0] : nil } }
    var isActive: Bool { !queue.isEmpty }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var client = NicoClient()
    @ObservationIgnored private var audioPreference = "auto"
    @ObservationIgnored private var loadMore: (@MainActor () async -> [VideoSummary])?
    /// Play order (indices into `queue`); shuffled in 随机播放.
    @ObservationIgnored private var order: [Int] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var failuresInARow = 0
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var artwork: MPMediaItemArtwork?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing, time.seconds.isFinite else { return }
                self.currentTime = time.seconds
            }
        }
        statusObservation = Self.observePlaying(player) { [weak self] playing in
            Task { @MainActor in
                self?.isPlaying = playing
                self?.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                Task { await self.trackEnded() }
            }
        }
        setUpRemoteCommands()
    }

    // MARK: Starting

    /// Plays `videos` from `startIndex`. `loadMore` fetches the next page of a paged list
    /// (search results, rankings…) when the queue runs out.
    func start(_ videos: [VideoSummary], title: String, startIndex: Int = 0, client: NicoClient,
               audioPreference: String, loadMore: (@MainActor () async -> [VideoSummary])? = nil) {
        guard !videos.isEmpty else { return }
        self.client = client
        self.audioPreference = audioPreference
        self.loadMore = loadMore
        queue = videos
        sourceTitle = title
        failuresInARow = 0
        rebuildOrder(startingWith: min(max(startIndex, 0), videos.count - 1))
        isPresented = true
        Task { await play(at: min(max(startIndex, 0), videos.count - 1)) }
    }

    /// Stops and forgets the queue (e.g. 播放视频 hands over to the video page).
    func stop() {
        generation += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        index = nil
        info = nil
        isPresented = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func pause() { player.pause() }

    // MARK: Controls

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else if player.currentItem == nil, let index {
            Task { await play(at: index) }
        } else {
            player.play()
        }
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlaying()
    }

    func next() async {
        await advance(by: 1)
    }

    func previous() async {
        await advance(by: -1)
    }

    func play(at queueIndex: Int) async {
        guard queue.indices.contains(queueIndex) else { return }
        generation += 1
        let token = generation
        index = queueIndex
        info = nil
        error = nil
        currentTime = 0
        duration = Double(queue[queueIndex].duration)
        isLoading = true
        artwork = nil
        updateNowPlaying()
        loadArtwork(queue[queueIndex].thumbnailURL, token: token)
        defer { if token == generation { isLoading = false } }
        do {
            let info = try await client.videoInfo(queue[queueIndex].id)
            guard token == generation else { return }
            self.info = info
            duration = Double(info.duration)
            isLiked = info.isLiked ?? false
            likeCount = info.counts.like
            isFollowing = info.isFollowingUploader
            loadFollowState(info, token: token)
            let playback = try await client.hlsPlayback(for: info, selection: audioSelection(for: info))
            guard token == generation else { return }
            let asset = AVURLAsset(url: playback.url, options: [AVURLAssetHTTPCookiesKey: playback.httpCookies])
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            player.play()
            failuresInARow = 0
            updateNowPlaying()
            // Counts the view and adds it to the account's history, as the site's player does.
            try? await client.reportPlayback(of: info)
        } catch {
            guard token == generation else { return }
            // Members-only, region-locked, deleted…: skip to the next one.
            failuresInARow += 1
            if failuresInARow < queue.count {
                await advance(by: 1)
            } else {
                self.error = error.localizedDescription
                failuresInARow = 0
            }
        }
    }

    func remove(at queueIndex: Int) {
        guard queue.indices.contains(queueIndex) else { return }
        let removingCurrent = queueIndex == index
        queue.remove(at: queueIndex)
        if let index, queueIndex < index { self.index = index - 1 }
        if queue.isEmpty {
            stop()
            return
        }
        rebuildOrder(startingWith: index ?? 0)
        if removingCurrent {
            let next = min(queueIndex, queue.count - 1)
            Task { await play(at: next) }
        }
    }

    func cycleMode() {
        let all = Mode.allCases
        mode = all[(all.firstIndex(of: mode)! + 1) % all.count]
    }

    // MARK: Like / follow (synced with the account)

    func toggleLike() async {
        guard let id = current?.id else { return }
        let liked = !isLiked
        isLiked = liked
        likeCount += liked ? 1 : -1
        do {
            try await client.setLiked(liked, video: id)
        } catch {
            isLiked = !liked
            likeCount += liked ? -1 : 1
        }
    }

    /// Returns the new state on success.
    @discardableResult
    func toggleFollow() async -> Bool? {
        guard case .user(let userID, _, _) = info?.uploader else { return nil }
        let following = !(isFollowing ?? false)
        isFollowing = following
        do {
            try await client.setFollowing(following, user: userID)
            return following
        } catch {
            isFollowing = !following
            return nil
        }
    }

    // MARK: Order

    private func rebuildOrder(startingWith start: Int? = nil) {
        let indices = Array(queue.indices)
        guard mode == .shuffle else {
            order = indices
            return
        }
        // A shuffled round with the current track first, so "next" never repeats within it.
        let first = start ?? index ?? 0
        order = [first] + indices.filter { $0 != first }.shuffled()
    }

    private func advance(by step: Int) async {
        guard !queue.isEmpty else { return }
        let position = index.flatMap { order.firstIndex(of: $0) } ?? 0
        var target = position + step
        if target >= order.count {
            if let loadMore {
                let more = await loadMore().filter { video in !queue.contains { $0.id == video.id } }
                if !more.isEmpty {
                    let start = queue.count
                    queue += more
                    let added = Array(start..<queue.count)
                    order += mode == .shuffle ? added.shuffled() : added
                }
            }
            if target >= order.count {
                target = 0 // 列表循环 / 随机播放: start over (a new shuffled round)
                if mode == .shuffle { rebuildOrder(startingWith: order.first) }
            }
        }
        if target < 0 { target = order.count - 1 }
        await play(at: order[target])
    }

    private func trackEnded() async {
        if mode == .loopOne {
            seek(to: 0)
            player.play()
        } else {
            await advance(by: 1)
        }
    }

    private func audioSelection(for info: VideoInfo) -> HLSSelection {
        let audios = info.audioStreams.filter(\.isAvailable).sorted { ($0.bitRate ?? 0) < ($1.bitRate ?? 0) }
        let audioID: String? = switch audioPreference {
        case "low": audios.first?.id
        case "high": audios.last?.id
        default: nil
        }
        return HLSSelection(audioID: audioID, audioOnly: true)
    }

    // MARK: Lock screen / Control Center

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.next() } }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.previous() } }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.ownerName ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The user API's own answer is the reliable one; the watch data sometimes lacks it.
    private func loadFollowState(_ info: VideoInfo, token: Int) {
        guard client.isLoggedIn, case .user(let userID, _, _) = info.uploader else { return }
        Task {
            guard let profile = try? await client.userProfile(userID), token == generation,
                  let following = profile.isFollowing else { return }
            isFollowing = following
        }
    }

    private func loadArtwork(_ url: URL?, token: Int) {
        guard let url else { return }
        Task {
            guard let image = await CoverLoader.image(for: url), token == generation else { return }
            artwork = Self.makeArtwork(image)
            updateNowPlaying()
        }
    }

    // The system calls these back on its own threads. Built outside the main actor, so the
    // callbacks aren't tied to it (Swift stops the app if a main-actor closure runs elsewhere —
    // that was the crash when opening 听视频: the lock screen asked for the cover).

    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    nonisolated private static func observePlaying(
        _ player: AVPlayer, _ handler: @escaping @Sendable (Bool) -> Void
    ) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            handler(player.timeControlStatus != .paused)
        }
    }
}

/// Where 播放视频 continues from: the listening position for that video, taken once.
@MainActor
enum PlaybackHandoff {
    private static var positions: [VideoID: Double] = [:]

    static func set(_ seconds: Double, for id: VideoID) { positions[id] = seconds }

    static func take(for id: VideoID) -> Double? { positions.removeValue(forKey: id) }
}
