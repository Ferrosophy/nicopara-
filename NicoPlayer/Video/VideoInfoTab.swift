import NicoKit
import SwiftUI

/// 简介: uploader, title and numbers, tags, actions, description, series, related videos.
struct VideoInfoTab: View {
    let page: VideoPageModel

    @Environment(AccountStore.self) private var account
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationStore.self) private var translator
    @Environment(FollowStore.self) private var follow
    @State private var descriptionExpanded = false

    var body: some View {
        ScrollView {
            if let info = page.info {
                VStack(alignment: .leading, spacing: 10) {
                    uploaderRow(info)
                    Text(info.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                    stats(info)
                    if info.access != .free {
                        Label(accessText(info.access), systemImage: "lock.fill").font(.footnote).foregroundStyle(.orange)
                    }
                    if !info.tags.isEmpty { tags(info.tags) }
                    VideoActionBar(page: page)
                    if let error = page.actionError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    if !info.descriptionText.isEmpty { description(info.descriptionText) }
                    if let series = page.series { seriesCard(series) }
                    related
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if page.loadError == nil {
                ProgressView().padding(40)
            }
        }
    }

    // MARK: Parts

    @ViewBuilder private func uploaderRow(_ info: VideoInfo) -> some View {
        switch info.uploader {
        case .user(let id, let name, let iconURL):
            HStack(spacing: 10) {
                NavigationLink(value: NicoUser(id: id, nickname: name, iconURL: iconURL)) {
                    HStack(spacing: 10) {
                        avatar(iconURL)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.tint).lineLimit(1)
                            Text(uploaderNumbers).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if account.isLoggedIn {
                    Group {
                        if page.isFollowing ?? false {
                            Button("已关注") { toggleFollow(NicoUser(id: id, nickname: name, iconURL: iconURL)) }
                                .buttonStyle(.bordered)
                        } else {
                            Button("关注") { toggleFollow(NicoUser(id: id, nickname: name, iconURL: iconURL)) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
        case .channel(_, let name, let iconURL):
            HStack(spacing: 10) {
                avatar(iconURL)
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("频道").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
            }
        case nil:
            EmptyView()
        }
    }

    private var uploaderNumbers: String {
        var parts: [String] = []
        if let profile = page.profile { parts.append("\(VideoCard.compact(profile.followerCount)) 粉丝") }
        if let count = page.uploadCount { parts.append("\(count) 投稿") }
        return parts.isEmpty ? " " : parts.joined(separator: "  ")
    }

    private func toggleFollow(_ user: NicoUser) {
        Task {
            if let following = await page.toggleFollow(account.client) {
                follow.followChanged(user, isFollowing: following)
            }
        }
    }

    private func avatar(_ url: URL?) -> some View {
        AsyncImage(url: url) { $0.resizable() } placeholder: { Color.secondary.opacity(0.2) }
            .frame(width: 40, height: 40)
            .clipShape(.circle)
    }

    private func stats(_ info: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                StatLabel(icon: "play.rectangle", value: VideoCard.compact(info.counts.view))
                StatLabel(icon: "text.bubble", value: VideoCard.compact(info.counts.comment))
                if let date = info.registeredAt {
                    Text(date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute()))
                }
            }
            .lineLimit(1)
            Text(info.id.rawValue).textSelection(.enabled)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private func tags(_ tags: [String]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                NavigationLink(value: SearchOptions.query(mode: .tag, text: tag)) {
                    Text(tag)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The description, with its translation underneath (沉浸式翻译) when enabled.
    private func description(_ text: String) -> some View {
        let translated = settings.translationEnabled
            ? translator.translation(of: text, to: settings.translationTarget) : nil
        return VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(descriptionExpanded ? nil : 3)
                .textSelection(.enabled)
            if let translated {
                Text(translated)
                    .font(.footnote)
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(descriptionExpanded ? nil : 3)
                    .textSelection(.enabled)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.tint.opacity(0.5)).frame(width: 2)
                    }
            }
            Button(descriptionExpanded ? "收起" : "展开简介") { descriptionExpanded.toggle() }
                .font(.caption)
        }
        .task(id: settings.translationEnabled ? settings.translationTarget + text : "") {
            guard settings.translationEnabled else { return }
            await translator.request([text], to: settings.translationTarget)
        }
    }

    private func seriesCard(_ series: SeriesPosition) -> some View {
        NavigationLink(value: Route.series(series.series, current: page.id)) {
            HStack(spacing: 8) {
                Text("合集：").font(.subheadline.weight(.semibold))
                Text(series.series.title).font(.subheadline).lineLimit(1)
                Spacer(minLength: 8)
                if let order = series.order, let total = series.totalCount {
                    Text("\(order)/\(total)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                } else if let total = series.totalCount {
                    Text("共 \(total)").font(.subheadline).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var related: some View {
        if !page.related.isEmpty {
            Divider()
            Text("相关推荐").font(.headline)
            ForEach(page.related) { video in
                NavigationLink(value: video.id) { VideoRow(video: video) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func accessText(_ access: VideoInfo.Access) -> String {
        switch access {
        case .free: ""
        case .premiumOnly: "仅高级会员可看"
        case .channelMemberOnly: "仅频道会员可看"
        case .paid: "付费视频"
        }
    }
}

/// 点赞 (いいね, synced) · 收藏 (local list) · 稍后观看 (synced) · 分享, as icon-over-label buttons.
struct VideoActionBar: View {
    let page: VideoPageModel

    @Environment(AccountStore.self) private var account
    @Environment(WatchLaterStore.self) private var watchLater
    @Environment(LocalLibrary.self) private var library
    @State private var isTogglingWatchLater = false

    var body: some View {
        if let info = page.info {
            HStack(spacing: 0) {
                action(page.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                       VideoCard.compact(page.likeCount), active: page.isLiked) {
                    Task { await page.toggleLike(account.client) }
                }
                .disabled(!account.isLoggedIn)

                let saved = library.item(for: info.id)
                Menu {
                    if let saved {
                        Section("在「\(saved.group)」里") {
                            ForEach(library.groups.filter { $0 != saved.group }, id: \.self) { name in
                                Button("移到「\(name)」") { library.move(info.id, to: name) }
                            }
                            Button("取消收藏", systemImage: "trash", role: .destructive) { library.remove([info.id]) }
                        }
                    } else {
                        Section("收藏到本地列表") {
                            ForEach(library.groups, id: \.self) { name in
                                Button(name) { library.add(info.summary, to: name) }
                            }
                        }
                    }
                } label: {
                    label(saved != nil ? "star.fill" : "star", saved != nil ? "已收藏" : "收藏", active: saved != nil)
                }
                .frame(maxWidth: .infinity)

                let later = watchLater.contains(info.id)
                action(later ? "clock.fill" : "clock", later ? "已在稍后" : "稍后观看", active: later) {
                    isTogglingWatchLater = true
                    Task {
                        await watchLater.toggle(info.id, account.client)
                        isTogglingWatchLater = false
                    }
                }
                .disabled(!account.isLoggedIn || isTogglingWatchLater || !watchLater.loaded)

                ShareLink(item: URL(string: info.id.watchURL)!, subject: Text(info.title)) {
                    label("square.and.arrow.up", "分享", active: false)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .task(id: account.client.userSession) { await watchLater.loadIfNeeded(account.client) }
        }
    }

    private func action(_ icon: String, _ title: String, active: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { label(icon, title, active: active) }
            .frame(maxWidth: .infinity)
    }

    private func label(_ icon: String, _ title: String, active: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption).lineLimit(1)
        }
        .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }
}

/// Lays children out left to right, wrapping to new lines (for tag chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (index, x) in row.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var items: [(index: Int, x: CGFloat)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width > 0, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            let x = row.width == 0 ? 0 : row.width + spacing
            row.items.append((index, x))
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
