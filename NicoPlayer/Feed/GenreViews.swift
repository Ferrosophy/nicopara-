import NicoKit
import SwiftUI

/// 分区: the site's ranking genres as a 4-column grid of black-and-white icons. The adult
/// genre (例のソレ) only appears when logged in and the site offers it to the account.
struct GenreGridView: View {
    @Environment(AccountStore.self) private var account
    @State private var genres: [RankingGenre] = []
    @State private var loadedSession: String??
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(shown) { genre in
                    NavigationLink(value: Route.genre(genre)) {
                        VStack(spacing: 8) {
                            Image(systemName: genre.symbol)
                                .font(.system(size: 26, weight: .regular))
                                .frame(height: 32)
                            Text(genre.chineseName)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)

            if let error {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.red).font(.footnote)
                    Button("重试") { Task { await load() } }
                }
            } else if genres.isEmpty {
                ProgressView().padding(30)
            }
        }
        .refreshable { await load() }
        .task(id: account.client.userSession) {
            if loadedSession != .some(account.client.userSession) { await load() }
        }
    }

    private var shown: [RankingGenre] {
        account.isLoggedIn ? genres : genres.filter { !$0.isImmoral }
    }

    private func load() async {
        loadedSession = .some(account.client.userSession)
        do {
            genres = try await account.client.rankingGenres()
            error = nil
        } catch {
            self.error = error.localizedDescription
            loadedSession = nil
        }
    }
}

/// One genre's ranking: time range (as on the site) and trend tags on top, ranked list below.
struct GenreRankingView: View {
    let genre: RankingGenre

    @Environment(AccountStore.self) private var account
    @AppStorage("rankingTerm") private var term = RankingTerm.day
    @State private var tag: String?
    @State private var videos: [VideoSummary] = []
    @State private var lastPage: RankingPage?
    @State private var isLoading = false
    @State private var error: String?
    @State private var loadedKey: String?

    private var key: String { "\(term.rawValue)|\(tag ?? "")" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("时间", selection: $term) {
                ForEach(RankingTerm.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            if !genre.trendTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        tagChip(nil, title: "全部")
                        ForEach(genre.trendTags, id: \.self) { tagChip($0, title: "#\($0)") }
                    }
                    .padding(.horizontal, 16)
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .padding(.bottom, 6)
            }

            List {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    NavigationLink(value: video.id) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.subheadline.monospacedDigit().weight(index < 3 ? .bold : .regular))
                                .foregroundStyle(index < 3 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .frame(width: 30, alignment: .trailing)
                            VideoRow(video: video)
                        }
                    }
                    .onAppear {
                        if video.id == videos.last?.id { Task { await loadNext() } }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                } else if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if lastPage != nil, videos.isEmpty {
                    Text("这个时间范围里没有视频").foregroundStyle(.secondary).font(.footnote)
                }
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            // Only the list: on the whole page it also reached the horizontal tag rows, which then
            // could be pulled down under the list.
            .refreshable { await reload() }
        }
        .navigationTitle(genre.chineseName)
        .navigationBarTitleDisplayMode(.inline)
        // Reload when the range or tag changes, not when coming back from a video.
        .task(id: key) { if loadedKey != key { await reload() } }
    }

    private func tagChip(_ value: String?, title: String) -> some View {
        Button { tag = value } label: {
            Text(title)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(tag == value ? Color.white : Color.primary)
                .background(tag == value ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        loadedKey = key
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await account.client.ranking(genre.key, term: term, tag: tag)
            videos = page.videos
            lastPage = page
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadNext() async {
        guard !isLoading, let lastPage, lastPage.hasNext else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await account.client.ranking(genre.key, term: term, tag: tag, page: lastPage.page + 1)
            let known = Set(videos.map(\.id))
            videos += page.videos.filter { !known.contains($0.id) }
            self.lastPage = page
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension RankingTerm {
    /// The site's 毎時 / 24時間 / 週間 / 月間 / 全期間.
    var label: String { L(chineseLabel) }

    private var chineseLabel: String {
        switch self {
        case .hour: "每小时"
        case .day: "24小时"
        case .week: "每周"
        case .month: "每月"
        case .total: "全部"
        }
    }
}

extension RankingGenre {
    /// Chinese name and SF Symbol by the site's label; unknown genres keep their own name.
    private static let names: [String: (String, String)] = [
        "総合": ("综合", "square.grid.2x2"),
        "ゲーム": ("游戏", "gamecontroller"),
        "アニメ": ("动画", "sparkles.tv"),
        "ボカロ": ("VOCALOID", "music.mic"),
        "音声合成実況・解説・劇場": ("合成音声实况・解说・剧场", "waveform"),
        "エンタメ": ("娱乐", "theatermasks"),
        "音楽": ("音乐", "music.note"),
        "歌ってみた": ("翻唱", "mic"),
        "踊ってみた": ("舞蹈", "figure.dance"),
        "演奏してみた": ("演奏", "guitars"),
        "解説・講座": ("解说・讲座", "graduationcap"),
        "料理": ("料理", "fork.knife"),
        "旅行・アウトドア": ("旅行・户外", "tent"),
        "自然": ("自然", "leaf"),
        "乗り物": ("交通工具", "car"),
        "技術・工作": ("技术・手工", "hammer"),
        "社会・政治・時事": ("社会・政治・时事", "newspaper"),
        "MMD": ("MMD", "cube"),
        "VTuber": ("VTuber", "person.crop.square"),
        "ラジオ": ("电台", "radio"),
        "スポーツ": ("体育", "sportscourt"),
        "動物": ("动物", "pawprint"),
        "その他": ("其他", "ellipsis.circle"),
        "例のソレ": ("例のソレ", "eye.slash"),
    ]

    /// Name in the app's language (Japanese shows the site's own name).
    var chineseName: String { Self.names[label].map { L($0.0) } ?? label }
    var symbol: String { Self.names[label]?.1 ?? (isImmoral ? "eye.slash" : "square.grid.2x2") }
}
