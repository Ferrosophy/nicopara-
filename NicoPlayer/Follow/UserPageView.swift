import NicoKit
import SwiftUI

/// An uploader's page: avatar and name, then their videos in the order picked (as on the site:
/// 7 sort keys, each either way; remembered across pages and launches).
struct UserPageView: View {
    let user: NicoUser

    @Environment(AccountStore.self) private var account
    @AppStorage("userVideoSort") private var sort = UserVideoSort.registeredAt
    @AppStorage("userVideoOrder") private var order = SearchQuery.SortOrder.desc
    @State private var profile: NicoUser?
    @State private var videos: [VideoSummary] = []
    @State private var lastPage: UserVideosPage?
    @State private var isLoading = false
    @State private var error: String?
    /// The sort the list was loaded with; coming back from a video must not reload it.
    @State private var loadedSort: String?

    private var shown: NicoUser { profile ?? user }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AsyncImage(url: shown.iconURL) { $0.resizable() } placeholder: { Color.secondary.opacity(0.2) }
                        .frame(width: 60, height: 60)
                        .clipShape(.circle)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(shown.nickname).font(.title3.bold())
                            if shown.isPremium {
                                Image(systemName: "crown.fill").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if let lastPage {
                            Text("\(lastPage.totalCount) 个投稿").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("ID \(shown.id)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(videos) { video in
                    NavigationLink(value: video.id) { VideoRow(video: video) }
                        .onAppear {
                            if video.id == videos.last?.id { Task { await loadNext() } }
                        }
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                } else if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if lastPage?.totalCount == 0 {
                    Text("还没有投稿").foregroundStyle(.secondary).font(.footnote)
                }
            } header: {
                HStack {
                    Text("投稿视频")
                    Spacer()
                    Menu {
                        ForEach(UserVideoSort.allCases, id: \.self) { key in
                            ForEach(SearchQuery.SortOrder.allCases, id: \.self) { direction in
                                Button {
                                    sort = key
                                    order = direction
                                } label: {
                                    if key == sort && direction == order {
                                        Label(key.label(direction), systemImage: "checkmark")
                                    } else {
                                        Text(key.label(direction))
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(sort.label(order), systemImage: "arrow.up.arrow.down").font(.footnote)
                    }
                }
                .textCase(nil)
            }
        }
        .navigationTitle(shown.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task(id: sortKey) {
            if loadedSort != sortKey { await reload() }
        }
    }

    private var sortKey: String { "\(sort.rawValue)-\(order.rawValue)" }

    private func reload() async {
        loadedSort = sortKey
        isLoading = true
        defer { isLoading = false }
        // The profile is a nicety (icon, premium); the video list is what matters.
        if profile == nil { profile = try? await account.client.user(user.id) }
        do {
            let page = try await account.client.userVideos(user.id, sort: sort, order: order)
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
            let page = try await account.client.userVideos(user.id, sort: sort, order: order, page: lastPage.page + 1)
            let known = Set(videos.map(\.id))
            videos += page.videos.filter { !known.contains($0.id) }
            self.lastPage = page
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension UserVideoSort {
    /// The site's wording, e.g. 投稿日时：新→旧.
    func label(_ order: SearchQuery.SortOrder) -> String {
        let (name, high, low): (String, String, String) = switch self {
        case .registeredAt: ("投稿时间", "新→旧", "旧→新")
        case .viewCount: ("播放数", "多→少", "少→多")
        case .lastCommentTime: ("最新评论", "新→旧", "旧→新")
        case .commentCount: ("评论数", "多→少", "少→多")
        case .likeCount: ("点赞数", "多→少", "少→多")
        case .mylistCount: ("收藏数", "多→少", "少→多")
        case .duration: ("时长", "长→短", "短→长")
        }
        return "\(L(name))：\(L(order == .desc ? high : low))"
    }
}
