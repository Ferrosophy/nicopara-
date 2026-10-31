import NicoKit
import SwiftUI

/// 首页: 推荐 | 分区 along the top (swipe between them), with the search pill above.
struct HomeView: View {
    enum Page: String, CaseIterable {
        case recommend = "推荐"
        case genres = "分区"
    }

    @State private var page = Page.recommend

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 32) {
                ForEach(Page.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { page = item }
                    } label: {
                        Text(L(item.rawValue))
                            .font(.subheadline.weight(page == item ? .semibold : .regular))
                            .foregroundStyle(page == item ? .primary : .secondary)
                            .frame(maxHeight: .infinity)
                            .overlay(alignment: .bottom) {
                                Capsule()
                                    .fill(page == item ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                                    .frame(width: 20, height: 3)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.bottom, 8)

            TabView(selection: $page) {
                FeedView().tag(Page.recommend)
                GenreGridView().tag(Page.genres)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Bilibili-style search pill across the top of the home page.
            ToolbarItem(placement: .principal) {
                NavigationLink(value: Route.search) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("搜索视频、标签，或粘贴链接")
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Home: the site's recommendations, personalized when logged in. The content lives in
/// ``FeedStore`` and only changes on pull to refresh; scrolling to the end appends more.
struct FeedView: View {
    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            if !account.isLoggedIn {
                Text("未登录：显示的是通用推荐。登录后是你的个性化推荐。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(feed.videos) { video in
                    NavigationLink(value: video.id) {
                        VideoCard(video: video)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if video.id == feed.videos.last?.id { Task { await feed.loadMore(account.client) } }
                    }
                }
            }
            .padding(.horizontal, 10)

            footer.padding(.vertical, 20)
        }
        .refreshable { await feed.refresh(account.client) }
        // Runs again on every appearance; it only fetches when there is no feed yet
        // or the login changed.
        .task(id: account.client.userSession) { await feed.loadIfNeeded(account.client) }
    }

    @ViewBuilder private var footer: some View {
        if let error = feed.error {
            VStack(spacing: 8) {
                Text(error).foregroundStyle(.red).font(.footnote)
                Button("重试") {
                    Task {
                        if feed.videos.isEmpty {
                            await feed.refresh(account.client)
                        } else {
                            await feed.loadMore(account.client)
                        }
                    }
                }
            }
        } else if feed.isLoadingMore || feed.videos.isEmpty {
            ProgressView()
        } else if feed.reachedEnd {
            Text("暂时没有更多推荐了，下拉刷新试试").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
