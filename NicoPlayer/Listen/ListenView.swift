import NicoKit
import SwiftUI

/// 听视频 page, top to bottom: cover · title · uploader + 关注 · 播放视频 · 点赞 / 收藏 / 更换列表 /
/// 分享 · progress · mode, previous, play / pause, next, list.
struct ListenView: View {
    @Environment(ListenStore.self) private var listen
    @Environment(AccountStore.self) private var account
    @Environment(FollowStore.self) private var follow
    @Environment(LocalLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var scrubValue: Double = 0
    @State private var showingQueue = false
    @State private var showingSources = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if let video = listen.current {
                // Fixed on screen (no scrolling): the title is capped at two lines instead.
                VStack(spacing: 12) {
                    cover(video)
                    titleBlock(video)
                    playVideoButton(video)
                    actionGrid(video)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                Spacer(minLength: 8)
                VStack(spacing: 12) {
                    progress
                    controls
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
                Spacer()
            }
        }
        .sheet(isPresented: $showingQueue) { ListenQueueSheet() }
        .sheet(isPresented: $showingSources) { ListenSourceSheet() }
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Button { listen.isPresented = false } label: {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            Spacer()
            Text(verbatim: listen.sourceTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer()
            Button { listen.stop() } label: {
                Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("退出听视频")
        }
        .padding(.horizontal, 8)
        .foregroundStyle(.primary)
    }

    private func cover(_ video: VideoSummary) -> some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                CoverImage(url: video.thumbnailURL)
            }
            .overlay {
                if listen.isLoading { ProgressView().controlSize(.large) }
            }
            .overlay(alignment: .bottom) {
                if let error = listen.error {
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.65), in: .rect(cornerRadius: 8))
                        .padding(10)
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    private func titleBlock(_ video: VideoSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Always two lines tall, so nothing below moves with a one-line title.
            Text(verbatim: video.title)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(verbatim: video.ownerName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if account.isLoggedIn, case .user = listen.info?.uploader {
                    let following = listen.isFollowing ?? false
                    Button(following ? "已关注" : "关注") {
                        Task {
                            if let now = await listen.toggleFollow(), case .user(let id, let name, let icon)? = listen.info?.uploader {
                                follow.followChanged(NicoUser(id: id, nickname: name, iconURL: icon), isFollowing: now)
                            }
                        }
                    }
                        .buttonStyle(.bordered)
                        .tint(following ? Color.secondary : nil)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 30)
        }
    }

    /// Hands over to the video page at the same moment.
    private func playVideoButton(_ video: VideoSummary) -> some View {
        Button {
            PlaybackHandoff.set(listen.currentTime, for: video.id)
            listen.stop()
            router.push(video.id, in: router.tab)
        } label: {
            Label("播放视频", systemImage: "play.rectangle")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }

    private func actionGrid(_ video: VideoSummary) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                gridButton(listen.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                           Text(verbatim: VideoCard.compact(listen.likeCount)), active: listen.isLiked) {
                    Task { await listen.toggleLike() }
                }
                .disabled(!account.isLoggedIn)
                .modifier(TileBox())

                let saved = library.item(for: video.id)
                Menu {
                    if let saved {
                        Button("取消收藏", role: .destructive) { library.remove([video.id]) }
                        ForEach(library.groups.filter { $0 != saved.group }, id: \.self) { name in
                            Button("移到「\(library.displayName(name))」") { library.move(video.id, to: name) }
                        }
                    } else {
                        ForEach(library.groups, id: \.self) { name in
                            Button(library.displayName(name)) { library.add(video, to: name) }
                        }
                    }
                } label: {
                    tile(saved != nil ? "star.fill" : "star", Text(saved != nil ? "已收藏" : "收藏"), active: saved != nil)
                }
                .menuStyle(.button)
                .modifier(TileBox())
            }
            GridRow {
                gridButton("list.bullet.rectangle", Text("更换列表"), active: false) { showingSources = true }
                    .modifier(TileBox())
                ShareLink(item: URL(string: video.id.watchURL)!, subject: Text(verbatim: video.title)) {
                    tile("square.and.arrow.up", Text("分享"), active: false)
                }
                .modifier(TileBox())
            }
        }
        .buttonStyle(.plain)
    }

    private func gridButton(_ icon: String, _ title: Text, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { tile(icon, title, active: active) }
    }

    private func tile(_ icon: String, _ title: Text, active: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).frame(height: 24)
            title.font(.caption).lineLimit(1)
        }
        .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
    }

    /// The same box for all four tiles; the background sits on the box, not on the control.
    private struct TileBox: ViewModifier {
        func body(content: Content) -> some View {
            content
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { listen.isScrubbing ? scrubValue : listen.currentTime },
                               set: { scrubValue = $0 }),
                in: 0...max(listen.duration, 1)
            ) { editing in
                if editing {
                    scrubValue = listen.currentTime
                    listen.isScrubbing = true
                } else {
                    listen.seek(to: scrubValue)
                    listen.isScrubbing = false
                }
            }
            HStack {
                Text(verbatim: PlayerModel.format(listen.isScrubbing ? scrubValue : listen.currentTime))
                Spacer()
                Text(verbatim: PlayerModel.format(listen.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack {
            circleButton(listen.mode.symbol, size: 44, label: Text(verbatim: listen.mode.label)) { listen.cycleMode() }
            Spacer()
            circleButton("backward.fill", size: 52, label: Text("上一首")) { Task { await listen.previous() } }
            Spacer()
            circleButton(listen.isPlaying ? "pause.fill" : "play.fill", size: 68, prominent: true,
                         label: Text(listen.isPlaying ? "暂停" : "播放")) { listen.togglePlay() }
            Spacer()
            circleButton("forward.fill", size: 52, label: Text("下一首")) { Task { await listen.next() } }
            Spacer()
            circleButton("list.bullet", size: 44, label: Text("列表")) { showingQueue = true }
        }
    }

    private func circleButton(_ icon: String, size: CGFloat, prominent: Bool = false, label: Text,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : .primary)
                .frame(width: size, height: size)
                .background(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.6)), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 正在播放: the queue as plain titles; tap to play, × to take out of the queue.
struct ListenQueueSheet: View {
    @Environment(ListenStore.self) private var listen
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("正在播放")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(listen.queue.enumerated()), id: \.element.id) { index, video in
                        HStack(spacing: 10) {
                            Group {
                                if index == listen.index {
                                    Image(systemName: "waveform").foregroundStyle(.tint)
                                } else {
                                    Circle().fill(.quaternary).frame(width: 6, height: 6)
                                }
                            }
                            .frame(width: 20)
                            Text(verbatim: video.title)
                                .lineLimit(1)
                                .foregroundStyle(index == listen.index ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            Spacer(minLength: 8)
                            Button {
                                listen.remove(at: index)
                            } label: {
                                Image(systemName: "xmark").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(.rect)
                        .onTapGesture { Task { await listen.play(at: index) } }
                        .id(video.id)
                    }
                }
                .listStyle(.plain)
                .onAppear { if let current = listen.current { proxy.scrollTo(current.id, anchor: .center) } }
            }
            Divider()
            Button("关闭") { dismiss() }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .presentationDetents([.medium, .large])
    }
}

/// 更换列表: play another list instead.
struct ListenSourceSheet: View {
    @Environment(ListenStore.self) private var listen
    @Environment(AccountStore.self) private var account
    @Environment(LocalLibrary.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("本地列表") {
                    source(String(localized: "全部 \(library.items.count)"), videos: library.items.map(\.video))
                    ForEach(library.groups, id: \.self) { group in
                        let videos = library.items.filter { $0.group == group }.map(\.video)
                        source("\(library.displayName(group)) \(videos.count)", videos: videos)
                    }
                }
            }
            .navigationTitle("更换列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func source(_ title: String, videos: [VideoSummary]) -> some View {
        Button {
            listen.start(videos, title: title, client: account.client, audioPreference: settings.defaultAudioQuality)
            dismiss()
        } label: {
            Text(verbatim: title)
        }
        .disabled(videos.isEmpty)
    }

}

/// While listening with the page closed: a small bar to get back to it.
struct ListenMiniBar: View {
    @Environment(ListenStore.self) private var listen

    var body: some View {
        if let video = listen.current, !listen.isPresented {
            HStack(spacing: 10) {
                CoverImage(url: video.thumbnailURL)
                    .background(Color.secondary.opacity(0.2))
                    .frame(width: 44, height: 32)
                    .clipShape(.rect(cornerRadius: 6))
                Text(verbatim: video.title).font(.footnote).lineLimit(1)
                Spacer(minLength: 4)
                Button { listen.togglePlay() } label: {
                    Image(systemName: listen.isPlaying ? "pause.fill" : "play.fill").font(.body)
                        .frame(width: 36, height: 36)
                }
                Button { Task { await listen.next() } } label: {
                    Image(systemName: "forward.fill").font(.body).frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .contentShape(.capsule)
            .onTapGesture { listen.isPresented = true }
            .padding(.horizontal, 16)
        }
    }
}
