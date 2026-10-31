import NicoKit
import SwiftUI

/// 关注: 更新列表 (latest uploads from followed users) and 关注列表 (followed users,
/// newest follow first).
struct FollowView: View {
    enum Page: String, CaseIterable {
        case updates = "更新列表"
        case following = "关注列表"
    }

    @Environment(AccountStore.self) private var account
    @State private var page = Page.updates

    var body: some View {
        Group {
            if !account.isLoggedIn {
                LoginRequiredView(feature: "关注")
            } else {
                // Both lists stay alive side by side (switching used to tear one down and build
                // the other mid-animation, which stuttered); swipe left / right to switch.
                TabView(selection: $page) {
                    UploadsList().tag(Page.updates)
                    FollowingList().tag(Page.following)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .navigationTitle("关注")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("关注", selection: $page.animation(.easeInOut(duration: 0.25))) {
                    ForEach(Page.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
    }
}

/// 更新列表: newest uploads first, more on scroll, pull to refresh.
private struct UploadsList: View {
    @Environment(AccountStore.self) private var account
    @Environment(FollowStore.self) private var store

    var body: some View {
        List {
            ForEach(store.uploads.items) { upload in
                FollowUploadRow(upload: upload)
                    .onAppear {
                        if upload.id == store.uploads.items.last?.id {
                            Task { await store.loadMoreUploads(account.client) }
                        }
                    }
            }
            ListFooter(state: store.uploads, empty: "关注的 UP 主最近没有投稿")
        }
        .listStyle(.plain)
        .refreshable { await store.refreshUploads(account.client) }
        .task { await store.loadUploadsIfNeeded(account.client) }
    }
}

/// 关注列表: newest follow first (the site's order).
private struct FollowingList: View {
    @Environment(AccountStore.self) private var account
    @Environment(FollowStore.self) private var store

    var body: some View {
        List {
            ForEach(store.following.items) { user in
                NavigationLink(value: user) { UserRow(user: user) }
                    .onAppear {
                        if user.id == store.following.items.last?.id {
                            Task { await store.loadMoreFollowing(account.client) }
                        }
                    }
            }
            ListFooter(state: store.following, empty: "还没有关注任何人")
        }
        .listStyle(.plain)
        .refreshable { await store.refreshFollowing(account.client) }
        .task { await store.loadFollowingIfNeeded(account.client) }
    }
}

/// Spinner while loading, the error, or an empty-list message.
private struct ListFooter<Item>: View {
    let state: FollowStore.Paged<Item>
    let empty: String

    var body: some View {
        Group {
            if let error = state.error {
                Text(error).foregroundStyle(.red).font(.footnote)
            } else if state.isLoading || !state.loaded {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if state.items.isEmpty {
                Text(empty).foregroundStyle(.secondary).font(.footnote)
            }
        }
        .listRowSeparator(.hidden)
    }
}

/// One upload: who posted it and when, then the video.
struct FollowUploadRow: View {
    let upload: FollowUpload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AsyncImage(url: upload.uploaderIconURL) { $0.resizable() } placeholder: { Color.secondary.opacity(0.2) }
                    .frame(width: 30, height: 30)
                    .clipShape(.circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(upload.uploaderName).font(.subheadline.weight(.medium))
                    if let date = upload.postedAt {
                        Text(date, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // Channels have no user page here; users link to theirs.
                if upload.uploaderType == "user" {
                    NavigationLink(value: NicoUser(id: upload.uploaderID, nickname: upload.uploaderName,
                                                   iconURL: upload.uploaderIconURL)) {
                        Text("主页").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .fixedSize()
                }
            }

            NavigationLink(value: upload.videoID) {
                HStack(alignment: .top, spacing: 10) {
                    Color.secondary.opacity(0.15)
                        .frame(width: 150)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            CoverImage(url: upload.thumbnailURL)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if let duration = upload.duration {
                                Text(VideoCard.duration(duration))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.black.opacity(0.6), in: .rect(cornerRadius: 3))
                                    .padding(4)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 6))
                    Text(upload.title)
                        .font(.subheadline)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            // Two links in one List row: without explicit styles, a tap anywhere fires both.
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct UserRow: View {
    let user: NicoUser

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.iconURL) { $0.resizable() } placeholder: { Color.secondary.opacity(0.2) }
                .frame(width: 44, height: 44)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.nickname).font(.body.weight(.medium)).lineLimit(1)
                    if user.isPremium {
                        Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.orange)
                    }
                }
                if let description = user.shortDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
