import AVFoundation
import AVKit
import Observation

/// Playback state for one video, shared by the inline and the fullscreen player so switching
/// between them keeps playing without a hitch.
@MainActor @Observable
final class PlayerModel {
    /// Speed while long-pressing (应用设置: 2x or 3x).
    var boostRate: Float = 2
    /// The chosen playback speed (倍速 menu); long-press 2x is on top of nothing, then back to this.
    var playbackRate: Float = 1 {
        didSet { if isPlaying && !isBoosted { player.rate = playbackRate } }
    }
    /// Replay from the start when the video ends.
    var loops = false
    /// Called when the video plays to its end without looping (for 自动播放下一个).
    @ObservationIgnored var onEnded: (() -> Void)?
    /// Picture in picture, once the inline picture layer exists.
    private(set) var isPictureInPicturePossible = false
    @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?
    /// Picture layers currently on screen, most recent last.
    @ObservationIgnored private var layers: [AVPlayerLayer] = []
    @ObservationIgnored private var startsPictureInPictureAutomatically = true
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    let player = AVPlayer()
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double
    /// True while the long-press 2x is active.
    private(set) var isBoosted = false
    /// While the user drags the progress bar, time updates from the player are ignored.
    var isScrubbing = false
    private(set) var failure: String?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// `fallbackDuration` (from the video's metadata) is shown until the stream reports its own.
    init(fallbackDuration: Int) {
        duration = Double(fallbackDuration)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.update(status) }
        })
    }

    /// Starts playing an HLS stream. The cookies unlock the master playlist and the AES key.
    /// `startAt` continues from a position (switching quality keeps the place).
    func load(_ url: URL, cookies: [HTTPCookie], startAt: Double = 0, autoplay: Bool = true) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
        let item = AVPlayerItem(asset: asset)
        if startAt > 0 {
            item.seek(to: CMTime(seconds: startAt, preferredTimescale: 600), completionHandler: nil)
        }
        failure = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ended() }
        }
        observations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = Self.describeFailure(of: item)
            Task { @MainActor in self?.failure = message }
        })
        observations.append(item.observe(\.duration, options: [.new]) { [weak self] item, _ in
            let seconds = item.duration.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            Task { @MainActor in self?.duration = seconds }
        })
        player.replaceCurrentItem(with: item)
        if autoplay { play() }
    }

    /// Hooks picture in picture to the on-screen picture layer.
    func attach(_ layer: AVPlayerLayer, startsAutomatically: Bool) {
        startsPictureInPictureAutomatically = startsAutomatically
        if !layers.contains(where: { $0 === layer }) { layers.append(layer) }
        usePictureInPicture(with: layers.last)
    }

    /// A picture layer left the screen (e.g. fullscreen closed): go back to the previous one.
    func detach(_ layer: AVPlayerLayer) {
        layers.removeAll { $0 === layer }
        usePictureInPicture(with: layers.last)
    }

    private func usePictureInPicture(with layer: AVPlayerLayer?) {
        guard AVPictureInPictureController.isPictureInPictureSupported(), let layer else {
            pictureInPicture = nil
            isPictureInPicturePossible = false
            return
        }
        if pictureInPicture?.playerLayer !== layer {
            pictureInPicture = AVPictureInPictureController(playerLayer: layer)
        }
        pictureInPicture?.canStartPictureInPictureAutomaticallyFromInline = startsPictureInPictureAutomatically
        isPictureInPicturePossible = pictureInPicture != nil
    }

    func togglePictureInPicture() {
        guard let pictureInPicture else { return }
        if pictureInPicture.isPictureInPictureActive {
            pictureInPicture.stopPictureInPicture()
        } else {
            pictureInPicture.startPictureInPicture()
        }
    }

    private func ended() {
        if loops {
            seek(to: 0)
            play()
        } else {
            onEnded?()
        }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        if duration > 0, currentTime >= duration - 0.5 { seek(to: 0) }
        player.play()
        player.rate = isBoosted ? boostRate : playbackRate
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        let target = min(max(0, seconds), duration)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Long press began: play at 2x while held (only when already playing, like Bilibili).
    func beginBoost() {
        guard isPlaying, !isBoosted else { return }
        isBoosted = true
        player.rate = boostRate
    }

    /// Long press ended: back to normal speed.
    func endBoost() {
        guard isBoosted else { return }
        isBoosted = false
        if isPlaying { player.rate = playbackRate }
    }

    private func tick(_ time: CMTime) {
        guard !isScrubbing, time.seconds.isFinite else { return }
        currentTime = time.seconds
    }

    private func update(_ status: AVPlayer.TimeControlStatus) {
        isPlaying = status != .paused
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        if status == .paused { isBoosted = false }
    }

    /// Includes the last error-log entry (often an HTTP status) to make device reports useful.
    nonisolated private static func describeFailure(of item: AVPlayerItem) -> String {
        var message = String(localized: "播放失败：\(item.error?.localizedDescription ?? String(localized: "未知错误"))")
        if let event = item.errorLog()?.events.last {
            message += "\n[\(event.errorDomain) \(event.errorStatusCode)] \(event.errorComment ?? "")"
            if let uri = event.uri { message += "\n\(uri.prefix(80))" }
        }
        return message
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.isFinite ? max(0, seconds) : 0)
        let pattern: Duration.TimeFormatStyle.Pattern = total >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(total).formatted(.time(pattern: pattern))
    }
}
