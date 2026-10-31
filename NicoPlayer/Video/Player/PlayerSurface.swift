import NicoKit
import SwiftUI

/// Quality choices for the ⚙ menu. `nil` selection = 自动 (the player picks by network).
struct PlayerQualityOptions {
    var videos: [VideoInfo.Stream] = []
    var audios: [VideoInfo.Stream] = []
    var selectedVideo: String?
    var selectedAudio: String?
    var onSelect: ((_ video: String?, _ audio: String?) -> Void)?
}

/// Video plus Bilibili-style controls, used both inline and fullscreen (the same view, so
/// switching doesn't rebuild the picture).
///
/// - single tap: show / hide the controls (they hide by themselves after 3 s of playback)
/// - double tap: play / pause
/// - long press: 2x (or 3x, 应用设置) while held, with a "2x 倍速中" pill
/// - drag left / right: seek; fullscreen also drag up / down: brightness (left) / volume (right)
struct PlayerSurface: View {
    let model: PlayerModel
    let title: String
    let isFullscreen: Bool
    /// Danmaku drawn over the picture (already filtered); counts are merged duplicates.
    var danmaku: [NicoComment] = []
    var danmakuCounts: [String: Int] = [:]
    /// Translations of top / bottom danmaku (comment ID → text), drawn as an extra local line.
    var danmakuTranslations: [String: String] = [:]
    var quality = PlayerQualityOptions()
    /// Inline only: ‹ and ⌂ in the top corners, shown with the controls.
    var onBack: (() -> Void)?
    var onHome: (() -> Void)?
    let onToggleFullscreen: () -> Void

    @Environment(AppSettings.self) private var settings
    @State private var controlsVisible = true
    @State private var menuOpen = false
    @State private var adjusting: Adjustment?
    @State private var adjustStart: Double = 0
    @State private var hideTask: Task<Void, Never>?
    @State private var showingDanmakuSettings = false

    private enum Adjustment: Equatable {
        case brightness(Double)
        case volume(Double)
        case seek(target: Double, delta: Double)
    }

    private static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        ZStack {
            Color.black
            PlayerLayerView(model: model, autoPictureInPicture: settings.autoPictureInPicture)
            if settings.danmakuEnabled, !danmaku.isEmpty {
                DanmakuOverlay(model: model, comments: danmaku, counts: danmakuCounts,
                               translations: danmakuTranslations, settings: settings.danmaku)
            }

            GestureSurface(
                onSingleTap: { setControls(visible: !controlsVisible) },
                onDoubleTap: {
                    model.togglePlay()
                    setControls(visible: true)
                },
                onLongPress: { began in began ? model.beginBoost() : model.endBoost() },
                onPan: pan
            )

            if model.isBuffering && !model.isBoosted {
                ProgressView().tint(.white).controlSize(.large)
            }

            if controlsVisible {
                controls.transition(.opacity)
            }

            VStack {
                if model.isBoosted {
                    Label("\(model.boostRate.formatted())x 倍速中", systemImage: "forward.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: .capsule)
                        .padding(.top, isFullscreen ? 24 : 10)
                        .transition(.opacity)
                }
                Spacer()
            }
            .allowsHitTesting(false)

            if let adjusting {
                adjustmentHUD(adjusting).allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .animation(.easeInOut(duration: 0.15), value: model.isBoosted)
        .onChange(of: model.isPlaying) { scheduleHide() }
        .onChange(of: showingDanmakuSettings) { scheduleHide() }
        .onAppear { scheduleHide() }
        .sheet(isPresented: $showingDanmakuSettings) {
            NavigationStack {
                DanmakuSettingsForm()
                    .navigationTitle("弹幕设置")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showingDanmakuSettings = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            if isFullscreen {
                HStack(spacing: 14) {
                    Button(action: onToggleFullscreen) {
                        Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                    }
                    Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer()
                    pictureInPictureButton
                    settingsMenu
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.linearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
            } else if let onBack, let onHome {
                PlayerNavButtons(onBack: onBack, onHome: onHome)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button { model.togglePlay(); scheduleHide() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                        .frame(width: 26)
                }

                PlayerProgress(model: model, onScrubStart: { hideTask?.cancel() }, onScrubEnd: scheduleHide)

                Button {
                    settings.danmakuEnabled.toggle()
                    scheduleHide()
                } label: {
                    Image(systemName: settings.danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                        .font(.body)
                }
                .accessibilityLabel(settings.danmakuEnabled ? "关闭弹幕" : "打开弹幕")

                if !isFullscreen { settingsMenu }

                Button(action: onToggleFullscreen) {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(isFullscreen ? "退出全屏" : "全屏")
            }
            .padding(.horizontal, isFullscreen ? 24 : 10)
            .padding(.vertical, isFullscreen ? 14 : 6)
            .background(.linearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    @ViewBuilder private var pictureInPictureButton: some View {
        if model.isPictureInPicturePossible {
            Button { model.togglePictureInPicture() } label: {
                Image(systemName: "pip.enter").font(.body)
            }
            .accessibilityLabel("画中画")
        }
    }

    /// ⚙: speed, quality, sound quality, loop, picture in picture, danmaku settings.
    private var settingsMenu: some View {
        Menu {
            Picker("倍速", selection: Binding(get: { model.playbackRate }, set: { model.playbackRate = $0 })) {
                ForEach(Self.rates, id: \.self) { rate in
                    Text(rate == 1 ? "正常" : "\(rate.formatted())x").tag(rate)
                }
            }
            .pickerStyle(.menu)

            if !quality.videos.isEmpty, let onSelect = quality.onSelect {
                Picker("画质", selection: Binding(get: { quality.selectedVideo ?? "" },
                                                set: { onSelect($0.isEmpty ? nil : $0, quality.selectedAudio) })) {
                    Text("自动").tag("")
                    ForEach(quality.videos, id: \.id) { stream in
                        Text(qualityLabel(stream)).tag(stream.id).selectionDisabled(!stream.isAvailable)
                    }
                }
                .pickerStyle(.menu)
            }
            if quality.audios.count > 1, let onSelect = quality.onSelect {
                Picker("音质", selection: Binding(get: { quality.selectedAudio ?? "" },
                                                set: { onSelect(quality.selectedVideo, $0.isEmpty ? nil : $0) })) {
                    Text("自动").tag("")
                    ForEach(quality.audios, id: \.id) { stream in
                        Text(audioLabel(stream)).tag(stream.id).selectionDisabled(!stream.isAvailable)
                    }
                }
                .pickerStyle(.menu)
            }

            Picker("循环播放", selection: Binding(get: { settings.loopPlayback }, set: { settings.loopPlayback = $0 })) {
                Text("开启").tag(true)
                Text("关闭").tag(false)
            }
            .pickerStyle(.menu)
            if !isFullscreen, model.isPictureInPicturePossible {
                Button("画中画") { model.togglePictureInPicture() }
            }
            Button("弹幕设置") { showingDanmakuSettings = true }
                // Menu content appears / disappears with the open menu: keep the controls
                // (and so the menu) on screen meanwhile.
                .onAppear {
                    menuOpen = true
                    hideTask?.cancel()
                }
                .onDisappear {
                    menuOpen = false
                    scheduleHide()
                }
        } label: {
            Image(systemName: "gearshape").font(.body)
        }
        .accessibilityLabel("播放设置")
    }

    private func qualityLabel(_ stream: VideoInfo.Stream) -> String {
        let name = stream.label ?? stream.height.map { "\($0)p" } ?? stream.id
        return stream.isAvailable ? name : "\(name) 🔒"
    }

    private func audioLabel(_ stream: VideoInfo.Stream) -> String {
        let name = stream.bitRate.map { "\(Int((Double($0) / 1000).rounded())) kbps" } ?? stream.id
        return stream.isAvailable ? name : "\(name) 🔒"
    }

    private func adjustmentHUD(_ adjustment: Adjustment) -> some View {
        Group {
            switch adjustment {
            case .seek(let target, let delta):
                VStack(spacing: 4) {
                    Text("\(PlayerModel.format(target)) / \(PlayerModel.format(model.duration))")
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Text("\(delta >= 0 ? "+" : "-")\(Int(abs(delta).rounded())) 秒").font(.footnote.monospacedDigit())
                }
            case .brightness(let value), .volume(let value):
                let isBrightness = if case .brightness = adjustment { true } else { false }
                VStack(spacing: 8) {
                    Image(systemName: isBrightness ? "sun.max.fill" : (value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"))
                        .font(.title2)
                    Text("\(L(isBrightness ? "亮度" : "音量")) \(Int((value * 100).rounded()))%").font(.footnote.monospacedDigit())
                    ProgressView(value: value).tint(.white).frame(width: 110)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.65), in: .rect(cornerRadius: 12))
    }

    // MARK: Behaviour

    private func setControls(visible: Bool) {
        menuOpen = false
        controlsVisible = visible
        if visible { scheduleHide() }
    }

    /// Hide the controls after 3 s while playing; keep them while paused, scrubbing, or while
    /// the ⚙ menu or danmaku settings are open.
    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible, model.isPlaying, !menuOpen, !showingDanmakuSettings else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, model.isPlaying, !model.isScrubbing, !menuOpen, !showingDanmakuSettings
            else { return }
            controlsVisible = false
        }
    }

    private func pan(_ update: GestureSurface.PanUpdate) {
        guard let progress = update.progress else {
            if case .seek(let target, _) = adjusting { model.seek(to: target) }
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                adjusting = nil
            }
            return
        }
        switch update.kind {
        case .seek:
            // A full-width drag moves up to 2 minutes (less for short videos).
            if progress == 0 { adjustStart = model.currentTime }
            let span = min(model.duration, 120)
            let target = min(max(adjustStart + progress * span, 0), model.duration)
            adjusting = .seek(target: target, delta: target - adjustStart)
        case .brightness:
            guard isFullscreen else { return }
            if progress == 0 { adjustStart = ScreenBrightness.value }
            let value = min(max(adjustStart + progress * 1.2, 0), 1)
            ScreenBrightness.value = value
            adjusting = .brightness(value)
        case .volume:
            guard isFullscreen else { return }
            if progress == 0 { adjustStart = SystemVolume.shared.value }
            let value = min(max(adjustStart + progress * 1.2, 0), 1)
            if !SystemVolume.shared.set(value) {
                // Fallback: the app's own volume, if the system slider is unavailable.
                model.player.volume = Float(value)
            }
            adjusting = .volume(value)
        }
    }
}

/// Time, progress bar and length. Its own view so the time ticking (several times a second)
/// only redraws this, not the rest of the controls; redrawing the ⚙ menu made it flicker.
private struct PlayerProgress: View {
    let model: PlayerModel
    let onScrubStart: () -> Void
    let onScrubEnd: () -> Void
    @State private var scrubValue: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(PlayerModel.format(model.isScrubbing ? scrubValue : model.currentTime))
                .font(.caption.monospacedDigit())

            Slider(
                value: Binding(
                    get: { model.isScrubbing ? scrubValue : model.currentTime },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(model.duration, 1)
            ) { editing in
                if editing {
                    scrubValue = model.currentTime
                    model.isScrubbing = true
                    onScrubStart()
                } else {
                    model.seek(to: scrubValue)
                    model.isScrubbing = false
                    onScrubEnd()
                }
            }

            Text(PlayerModel.format(model.duration))
                .font(.caption.monospacedDigit())
        }
    }
}
