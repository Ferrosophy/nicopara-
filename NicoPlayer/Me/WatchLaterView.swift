import NicoKit
import SwiftUI

/// 稍后观看: the account's あとで見る, newest added first. Swipe to remove (synced).
struct WatchLaterView: View {
    @Environment(AccountStore.self) private var account
    @Environment(WatchLaterStore.self) private var store

    var body: some View {
        Group {
            if !account.isLoggedIn {
                LoginRequiredView(feature: "稍后观看")
            } else {
                List {
                    if store.loaded {
                        Text("共 \(store.totalCount) 个，和 Niconico 账号同步")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.items) { item in
                        NavigationLink(value: item.video.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                VideoRow(video: item.video)
                                if let memo = item.memo {
                                    Text(memo).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("移出", role: .destructive) {
                                Task { await store.remove([item], account.client) }
                            }
                        }
                    }
                    if let error = store.error {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    } else if store.isLoading && store.items.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if store.loaded && store.items.isEmpty {
                        Text("稍后观看是空的。在视频页点「稍后观看」加入。").foregroundStyle(.secondary).font(.footnote)
                    }
                }
                .listStyle(.plain)
                .refreshable { await store.reload(account.client) }
                .task { await store.loadIfNeeded(account.client) }
            }
        }
        .navigationTitle("稍后观看")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 历史观看: the account's 視聴履歴, most recent first, more on scroll.
struct HistoryView: View {
    @Environment(AccountStore.self) private var account
    @State private var items: [HistoryItem] = []
    @State private var cursor: String?
    @State private var loaded = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if !account.isLoggedIn {
                LoginRequiredView(feature: "历史观看")
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink(value: item.video.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                VideoRow(video: item.video)
                                if let date = item.lastViewedAt {
                                    Text("看过：\(date.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onAppear {
                            if item.id == items.last?.id { Task { await loadMore() } }
                        }
                    }
                    if let error {
                        Text(error).foregroundStyle(.red).font(.footnote).textSelection(.enabled)
                    } else if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if loaded && items.isEmpty {
                        Text("还没有观看记录").foregroundStyle(.secondary).font(.footnote)
                    }
                }
                .listStyle(.plain)
                .refreshable { await reload() }
                .task { if !loaded { await reload() } }
            }
        }
        .navigationTitle("历史观看")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await account.client.watchHistory()
            items = page.items
            cursor = page.nextCursor
            loaded = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoading, let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await account.client.watchHistory(cursor: cursor)
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            self.cursor = page.nextCursor
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
