import NicoKit
import SwiftUI

/// 弹幕 = the video's danmaku as a list. Sort by 最热 (ニコる), 最新 (post time) or 时间点;
/// tap one to jump the video to it. With 沉浸式翻译 on, each danmaku gets its translation
/// underneath, fetched on demand for the 20 before and after wherever the user scrolls.
struct CommentsTab: View {
    enum Sort: String, CaseIterable {
        case hot = "最热"
        case newest = "最新"
        case timeline = "按时间点"
    }

    let page: VideoPageModel
    /// The danmaku to list, with NG / pools already filtered (弹幕设置 → 屏蔽).
    let comments: [NicoComment]
    let onSeek: (Double) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(TranslationStore.self) private var translator
    @State private var sort = Sort.hot

    private var sorted: [NicoComment] {
        switch sort {
        case .hot: comments.sorted { ($0.nicoruCount, $0.vposMs) > ($1.nicoruCount, $1.vposMs) }
        case .newest: comments.sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
        case .timeline: comments
        }
    }

    var body: some View {
        let shown = sorted
        // A plain header row above the list instead of a List section header, which comes with
        // large system margins above and below it.
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(sort == .hot ? "最热弹幕" : sort == .newest ? "最新弹幕" : "按时间点")
                    .font(.subheadline.weight(.semibold))
                if page.commentsLoaded {
                    Text("已加载 \(comments.count) 条").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                    }
                } label: {
                    Label(L(sort.rawValue), systemImage: "line.3.horizontal.decrease").font(.subheadline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, comment in
                    Button { onSeek(Double(comment.vposMs) / 1000) } label: {
                        CommentRow(comment: comment, translation: translation(of: comment))
                    }
                    .buttonStyle(.plain)
                    .onAppear { translateAround(index, in: shown) }
                }
                if !page.commentsLoaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error = page.commentsError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                } else if comments.isEmpty {
                    Text("还没有弹幕").font(.footnote).foregroundStyle(.secondary)
                }
                if settings.translationEnabled, let error = translator.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
        }
    }

    private func translation(of comment: NicoComment) -> String? {
        guard settings.translationEnabled else { return nil }
        return translator.translation(of: comment.body, to: settings.translationTarget)
    }

    /// Translates the 20 danmaku before and after `index` that are not cached yet.
    private func translateAround(_ index: Int, in comments: [NicoComment]) {
        guard settings.translationEnabled else { return }
        let target = settings.translationTarget
        if translator.isTranslated(comments[index].body, to: target) { return }
        let range = max(0, index - 20)..<min(comments.count, index + 21)
        let texts = comments[range].map(\.body)
        Task { await translator.request(texts, to: target) }
    }
}

private struct CommentRow: View {
    let comment: NicoComment
    let translation: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(PlayerModel.format(Double(comment.vposMs) / 1000))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.body).font(.subheadline)
                if let translation {
                    Text(translation).font(.footnote).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if comment.nicoruCount > 0 {
                        Label("\(comment.nicoruCount)", systemImage: "hand.thumbsup")
                    }
                    if let date = comment.postedAt {
                        Text(date.formatted(date: .numeric, time: .omitted))
                    }
                    if comment.fork == "owner" { Text("UP 主") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// A series (合集) in order, the current video highlighted.
struct SeriesView: View {
    let series: SeriesRef
    let current: VideoID?

    @Environment(AccountStore.self) private var account
    @State private var entries: [SeriesPage.Entry] = []
    @State private var lastPage: SeriesPage?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            if let lastPage {
                Text("共 \(lastPage.totalCount) 个视频").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                NavigationLink(value: entry.video.id) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(entry.order)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(entry.id == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .frame(width: 30, alignment: .trailing)
                        VideoRow(video: entry.video)
                    }
                }
                .listRowBackground(entry.id == current ? Rectangle().fill(.tint.opacity(0.12)) : nil)
                .onAppear {
                    if entry.id == entries.last?.id { Task { await loadNext() } }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            } else if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .listStyle(.plain)
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if lastPage == nil { await load(page: 1) } }
    }

    private func loadNext() async {
        guard let lastPage, lastPage.canLoadMore else { return }
        await load(page: lastPage.page + 1)
    }

    private func load(page: Int) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await account.client.series(series.id, page: page)
            entries = page == 1 ? result.entries : entries + result.entries
            lastPage = result
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
