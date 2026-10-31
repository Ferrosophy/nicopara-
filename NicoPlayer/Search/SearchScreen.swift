import NicoKit
import SwiftUI

/// Search screen, pushed from 首页. 关键词: video search with the site's sort and filters
/// (a pasted video link or a bare `sm…` ID opens the video instead). 标签: searches tags
/// themselves and lists the matching ones; tapping a tag shows its videos.
struct SearchScreen: View {
    @State private var text = ""
    @State private var mode = SearchQuery.Mode.keyword
    @Environment(Router.self) private var router
    @Environment(\.currentTab) private var currentTab
    @State private var submitted: SearchQuery?
    @State private var isSearchPresented = true

    /// The video a pasted link or ID points to; nil for ordinary search words.
    private var linkedVideo: VideoID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = VideoID(parsing: trimmed) else { return nil }
        let isLink = trimmed.contains("nicovideo.jp/watch/") || trimmed.contains("nico.ms/")
        return isLink || trimmed == id.rawValue ? id : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Our own 关键词 / 标签 bar: the system one under the search field collapsed and
            // reappeared when clearing the text, making everything below jump.
            Picker("搜索类型", selection: $mode) {
                ForEach(SearchQuery.Mode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Group {
                if mode == .tag {
                    TagSuggestionList(text: text)
                } else if let submitted {
                    SearchResultsView(initial: submitted)
                        .id(submitted) // new search → fresh results and paging
                } else {
                    ContentUnavailableView("搜索 Niconico", systemImage: "magnifyingglass",
                                           description: Text("粘贴视频链接或输入 sm 编号可直接打开视频。"))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        // Any push from here (a result, a tag): close the search field, which otherwise keeps
        // the navigation bar (and its back button) on the next page.
        .onChange(of: router.feedPath.count) { isSearchPresented = false }
        .onDisappear { isSearchPresented = false }
        .searchable(text: $text, isPresented: $isSearchPresented,
                    prompt: mode == .tag ? "搜索标签" : "搜索视频、标签，或粘贴链接")
        .searchSuggestions {
            if let linkedVideo {
                Button {
                    isSearchPresented = false
                    router.push(linkedVideo, in: currentTab)
                } label: {
                    Label("打开视频 \(linkedVideo.rawValue)", systemImage: "play.rectangle")
                }
            }
        }
        .onSubmit(of: .search) {
            if let linkedVideo {
                isSearchPresented = false
                router.push(linkedVideo, in: currentTab)
                return
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, mode == .keyword else { return }
            submitted = SearchOptions.query(mode: .keyword, text: trimmed)
        }
    }
}

/// 标签 mode: the tags matching what was typed (the site's tag suggestions), updated as the
/// user types. The typed text itself comes first, in case it is already the exact tag.
private struct TagSuggestionList: View {
    let text: String

    @Environment(AccountStore.self) private var account
    @State private var tags: [String] = []
    @State private var error: String?

    private var typed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            if !typed.isEmpty {
                ForEach([typed] + tags.filter { $0 != typed }, id: \.self) { tag in
                    NavigationLink(value: SearchOptions.query(mode: .tag, text: tag)) {
                        Label(tag, systemImage: "number")
                    }
                }
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .listStyle(.plain)
        .overlay {
            if typed.isEmpty {
                ContentUnavailableView("搜索标签", systemImage: "number", description: Text("输入文字，列出匹配的标签"))
            }
        }
        .task(id: typed) {
            guard !typed.isEmpty else { tags = []; return }
            // Wait for a pause in typing before asking.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                tags = try await account.client.suggestTags(typed)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Results for one search, with a filter bar. Changing a filter reloads from page 1 and is
/// remembered for the next search.
struct SearchResultsView: View {
    @Environment(AccountStore.self) private var account
    @State private var query: SearchQuery
    @State private var videos: [VideoSummary] = []
    @State private var lastPage: SearchPage?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingDates = false
    @State private var loadedKey: TaskKey?

    init(initial: SearchQuery) {
        _query = State(initialValue: initial)
    }

    var body: some View {
        // The filter bar sits above the list (pinned) rather than as a List section header,
        // which brought large system margins; the count and related tags are tight rows.
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            if let lastPage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lastPage.totalCount == 0 ? "没有找到结果" : "共 \(lastPage.totalCount.formatted()) 个结果")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !lastPage.relatedTags.isEmpty {
                        relatedTags(lastPage.relatedTags)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            List {

                ForEach(videos) { video in
                    NavigationLink(value: video.id) { VideoRow(video: video) }
                        .onAppear {
                            if video.id == videos.last?.id { Task { await loadNext() } }
                        }
                }

                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(.red).font(.footnote)
                        Button("重试") { Task { videos.isEmpty ? await reload() : await loadNext() } }
                    }
                } else if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            // Only the list: on the whole page it also reached the horizontal tag rows, which then
            // could be pulled down under the list.
            .refreshable { await reload() }
        }
        // Reload when the query or login changes, but not when coming back from a video.
        .task(id: TaskKey(query: query, loggedIn: account.isLoggedIn)) {
            let key = TaskKey(query: query, loggedIn: account.isLoggedIn)
            if loadedKey != key { await reload() }
        }
        .onChange(of: query) { SearchOptions.remember(query) }
        .sheet(isPresented: $showingDates) { DateRangeSheet(query: $query) }
    }

    /// Reload when the query changes, or when logging in/out (おすすめ is personal).
    private struct TaskKey: Equatable {
        var query: SearchQuery
        var loggedIn: Bool
    }

    // MARK: Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("排序", selection: $query.sort) {
                        ForEach(SearchQuery.SortKey.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: {
                    chip(L("排序") + "：" + query.sort.label, active: query.sort != .hotLikeAndMylist)
                }

                if query.sort.isOrderable {
                    Button {
                        query.order = query.order == .desc ? .asc : .desc
                    } label: {
                        chip(query.order.label, systemImage: query.order.systemImage, active: query.order != .desc)
                    }
                }

                optionMenu("类型", selection: $query.kind, cases: SearchQuery.Kind.allCases, label: \.label, default: .any)
                optionMenu("时长", selection: $query.length, cases: SearchQuery.LengthRange.allCases, label: \.label, default: .any)
                optionMenu("投稿时间", selection: $query.posted, cases: SearchQuery.PostedRange.allCases, label: \.label, default: .any)
                optionMenu("类别", selection: $query.genre, cases: SearchQuery.Genre.allCases, label: \.label, default: .all)

                Button { showingDates = true } label: {
                    chip(dateLabel, systemImage: "calendar", active: query.startDate != nil || query.endDate != nil)
                }

                if query.hasFilters {
                    Button("重置筛选") {
                        query.kind = .any
                        query.length = .any
                        query.posted = .any
                        query.genre = .all
                        query.startDate = nil
                        query.endDate = nil
                    }
                    .font(.footnote)
                }
            }
        }
        // Full height, never squashed by the page; and no up / down scrolling inside the row.
        .fixedSize(horizontal: false, vertical: true)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    private var dateLabel: String {
        switch (query.startDate, query.endDate) {
        case (nil, nil): L("日期范围")
        case let (start?, nil): String(format: L("%@ 起"), start)
        case let (nil, end?): String(format: L("至 %@"), end)
        case let (start?, end?): "\(start) ~ \(end)"
        }
    }

    private func optionMenu<Option: Hashable>(
        _ title: String, selection: Binding<Option>, cases: [Option],
        label: KeyPath<Option, String>, default defaultValue: Option
    ) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(cases, id: \.self) { Text($0[keyPath: label]).tag($0) }
            }
        } label: {
            let value = selection.wrappedValue
            chip(value == defaultValue ? L(title) : L(title) + "：" + value[keyPath: label], active: value != defaultValue)
        }
    }

    private func chip(_ text: String, systemImage: String? = nil, active: Bool) -> some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
            if systemImage == nil { Image(systemName: "chevron.down").font(.caption2) }
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(active ? Color.white : Color.primary)
        .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
    }

    private func relatedTags(_ tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    NavigationLink(value: SearchOptions.query(mode: .tag, text: tag)) {
                        Text("#\(tag)").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        // Full height, never squashed by the page; and no up / down scrolling inside the row.
        .fixedSize(horizontal: false, vertical: true)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    // MARK: Loading

    private func reload() async {
        loadedKey = TaskKey(query: query, loggedIn: account.isLoggedIn)
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await account.client.search(query)
            videos = page.videos
            lastPage = page
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadNext() async {
        guard !isLoading, let lastPage, lastPage.canLoadMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await account.client.search(query, page: lastPage.page + 1)
            let known = Set(videos.map(\.id))
            videos += page.videos.filter { !known.contains($0.id) }
            self.lastPage = page
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 投稿日 range (`start` / `end`), each end optional, as Japan-time dates.
private struct DateRangeSheet: View {
    @Binding var query: SearchQuery
    @Environment(\.dismiss) private var dismiss
    @State private var useStart = false
    @State private var useEnd = false
    @State private var start = Date()
    @State private var end = Date()

    private static var japan: Date.ISO8601FormatStyle {
        var style = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        style = style.year().month().day().dateSeparator(.dash)
        return style
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("开始日期", isOn: $useStart)
                    if useStart {
                        DatePicker("开始", selection: $start, in: ...Date(), displayedComponents: .date)
                    }
                    Toggle("结束日期", isOn: $useEnd)
                    if useEnd {
                        DatePicker("结束", selection: $end, in: ...Date(), displayedComponents: .date)
                    }
                } footer: {
                    Text("按日本时间的投稿日期筛选，和网页版的「開始日 / 終了日」相同。")
                }
            }
            .navigationTitle("日期范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        query.startDate = useStart ? start.formatted(Self.japan) : nil
                        query.endDate = useEnd ? end.formatted(Self.japan) : nil
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let s = query.startDate, let date = try? Self.japan.parse(s) { useStart = true; start = date }
                if let e = query.endDate, let date = try? Self.japan.parse(e) { useEnd = true; end = date }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
