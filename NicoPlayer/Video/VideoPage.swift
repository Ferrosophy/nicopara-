import NicoKit
import SwiftUI

/// A video, Bilibili-style: the player pinned on top (‹ back to the previous video, ⌂ home to
/// 首页), then 简介 | 弹幕 (swipe between them) with the danmaku switch on the right. Plays as
/// soon as it opens (unless turned off in 应用设置).
///
/// Fullscreen is a separate landscape screen sharing the same player, shown without the
/// slide-up animation so switching is quick.
struct VideoPage: View {
    enum Section: Hashable { case info, comments }

    @Environment(AccountStore.self) private var account
    @Environment(Router.self) private var router
    @Environment(\.currentTab) private var currentTab
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationStore.self) private var translator
    @Environment(ListenStore.self) private var listen
    @State private var page: VideoPageModel
    @State private var section = Section.info
    @State private var isFullscreen = false

    init(id: VideoID) {
        _page = State(initialValue: VideoPageModel(id: id))
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
            sectionBar
            Divider()
            TabView(selection: $section) {
                VideoInfoTab(page: page).tag(Section.info)
                CommentsTab(page: page, comments: listComments) { seconds in
                    page.player?.seek(to: seconds)
                    page.player?.play()
                }
                .tag(Section.comments)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // Only our own ‹ and ⌂: never the system back button (search used to leave it showing).
        .navigationBarBackButtonHidden(true)
        .task(id: account.client.userSession) {
            listen.pause()
            page.boostRate = Float(settings.boostRate)
            page.loops = settings.loopPlayback
            await page.load(account.client, autoplay: settings.autoplay,
                            selection: { settings.defaultSelection(for: $0) }, loadNG: settings.syncAccountNG)
        }
        .onChange(of: settings.loopPlayback) { page.loops = settings.loopPlayback }
        .onChange(of: settings.boostRate) { page.boostRate = Float(settings.boostRate) }
        .onChange(of: page.endedCount) { playNext() }
        // Translate the top / bottom danmaku up front: they are few, and their translation
        // must be ready when they appear (scrolling danmaku are not translated).
        .task(id: TranslationKey(loaded: page.commentsLoaded, enabled: settings.translationEnabled,
                                 target: settings.translationTarget)) {
            guard page.commentsLoaded, settings.translationEnabled else { return }
            await translator.request(page.comments.filter { $0.position != .scroll }.map(\.body),
                                     to: settings.translationTarget)
        }
        // Opening another video (or leaving) pauses this one; going fullscreen does not.
        .onDisappear { if !isFullscreen { page.player?.pause() } }
        .fullScreenCover(isPresented: $isFullscreen, onDismiss: { OrientationLock.set(.portrait) }) {
            if let player = page.player {
                FullscreenPlayer(
                    model: player, title: page.info?.title ?? "",
                    danmaku: overlay.comments, danmakuCounts: overlay.counts,
                    danmakuTranslations: overlayTranslations, quality: qualityOptions,
                    onExit: toggleFullscreen
                )
            }
        }
    }

    // MARK: Player

    private var playerArea: some View {
        ZStack {
            if let player = page.player {
                PlayerSurface(
                    model: player, title: page.info?.title ?? "", isFullscreen: false,
                    danmaku: overlay.comments, danmakuCounts: overlay.counts,
                    danmakuTranslations: overlayTranslations,
                    quality: qualityOptions,
                    onBack: { dismiss() }, onHome: { router.goHome(from: currentTab) },
                    onToggleFullscreen: toggleFullscreen
                )
            } else {
                Color.black
                CoverImage(url: page.info?.thumbnailURL)
                if let message = page.loadError ?? page.playError {
                    VStack(spacing: 10) {
                        Text(message).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center)
                        Button("重试") {
                            Task {
                                if page.info == nil {
                                    await page.load(account.client)
                                } else {
                                    await page.startPlayback(account.client)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(.black.opacity(0.6), in: .rect(cornerRadius: 10))
                } else if page.info != nil, !page.isStarting, !settings.autoplay {
                    Button {
                        Task { await page.startPlayback(account.client) }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .padding(22)
                            .background(.black.opacity(0.5), in: .circle)
                    }
                } else {
                    ProgressView().tint(.white).controlSize(.large)
                }
                VStack {
                    PlayerNavButtons(onBack: { dismiss() }, onHome: { router.goHome(from: currentTab) })
                    Spacer()
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.black.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottomLeading) {
            if let failure = page.player?.failure {
                Text(failure).font(.caption2).foregroundStyle(.white).padding(6)
                    .background(.red.opacity(0.8), in: .rect(cornerRadius: 6)).padding(6)
            }
        }
    }

    private func toggleFullscreen() {
        let entering = !isFullscreen
        if entering { OrientationLock.set(.landscape) }
        // No slide-up animation: the rotation itself is the transition.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isFullscreen = entering }
    }

    private var qualityOptions: PlayerQualityOptions {
        PlayerQualityOptions(
            videos: page.info?.videoStreams ?? [],
            audios: page.info?.audioStreams ?? [],
            selectedVideo: page.selection.videoID,
            selectedAudio: page.selection.audioID,
            onSelect: { video, audio in
                Task { await page.switchQuality(account.client, videoID: video, audioID: audio) }
            }
        )
    }

    /// 播完自动播放下一个: the next video of the series if known, else the first related one.
    private func playNext() {
        guard settings.autoplayNext, !settings.loopPlayback else { return }
        Task {
            guard let next = await page.nextVideo(account.client) else { return }
            if isFullscreen { toggleFullscreen() }
            router.push(next, in: currentTab)
        }
    }

    // MARK: Danmaku

    private var filterOptions: DanmakuFilterOptions { settings.filterOptions(ng: page.ngItems) }

    /// What the overlay draws: 屏蔽 applied, duplicates merged.
    private var overlay: (comments: [NicoComment], counts: [String: Int]) {
        DanmakuFilter.forOverlay(page.comments, filterOptions)
    }

    /// What the 弹幕 list shows: NG and pools filtered, on-screen type blocks not.
    private var listComments: [NicoComment] {
        DanmakuFilter.forList(page.comments, filterOptions)
    }

    /// Translations for the top / bottom danmaku on screen (comment ID → text).
    private var overlayTranslations: [String: String] {
        guard settings.translationEnabled else { return [:] }
        var result: [String: String] = [:]
        for comment in page.comments where comment.position != .scroll {
            if let text = translator.translation(of: comment.body, to: settings.translationTarget) {
                result[comment.id] = text
            }
        }
        return result
    }

    private struct TranslationKey: Equatable {
        var loaded: Bool
        var enabled: Bool
        var target: String
    }

    // MARK: 简介 | 弹幕

    private var sectionBar: some View {
        HStack(spacing: 24) {
            sectionButton("简介", .info)
            sectionButton("弹幕 \(page.info.map { VideoCard.compact($0.counts.comment) } ?? "")", .comments)
            Spacer()
            Button {
                settings.danmakuEnabled.toggle()
            } label: {
                // On: filled; off: outlined.
                Image(systemName: settings.danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                    .font(.title3)
                    .foregroundStyle(settings.danmakuEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.danmakuEnabled ? "关闭弹幕" : "打开弹幕")
        }
        .frame(height: 42)
        .padding(.horizontal, 16)
    }

    /// Text centred in the bar; the underline is drawn over the bottom edge and takes no
    /// space, so the danmaku switch lines up with the text.
    private func sectionButton(_ title: LocalizedStringKey, _ value: Section) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { section = value }
        } label: {
            Text(title)
                .font(.subheadline.weight(section == value ? .semibold : .regular))
                .foregroundStyle(section == value ? .primary : .secondary)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(section == value ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                        .frame(width: 24, height: 3)
                }
        }
        .buttonStyle(.plain)
    }
}

/// ‹ and ⌂ over the top corners of the player.
struct PlayerNavButtons: View {
    let onBack: () -> Void
    let onHome: () -> Void

    var body: some View {
        HStack {
            button("chevron.left", label: "返回", action: onBack)
            Spacer()
            button("house", label: "回到首页", action: onHome)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private func button(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.35), in: .circle)
        }
        .accessibilityLabel(label)
    }
}

/// Landscape fullscreen: status bar and home indicator hidden, brightness / volume gestures on.
struct FullscreenPlayer: View {
    let model: PlayerModel
    let title: String
    var danmaku: [NicoComment] = []
    var danmakuCounts: [String: Int] = [:]
    var danmakuTranslations: [String: String] = [:]
    var quality = PlayerQualityOptions()
    let onExit: () -> Void

    var body: some View {
        ZStack {
            // Needed for the volume gesture; while it is on screen iOS doesn't show its own
            // volume popup.
            HiddenVolumeView().frame(width: 1, height: 1)
            PlayerSurface(model: model, title: title, isFullscreen: true, danmaku: danmaku,
                          danmakuCounts: danmakuCounts, danmakuTranslations: danmakuTranslations,
                          quality: quality, onToggleFullscreen: onExit)
                .ignoresSafeArea()
        }
        .background(.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { OrientationLock.set(.landscape) }
    }
}
