import NicoKit
import SwiftUI

/// 我的: account on top, then the user's lists. 稍后观看 and 历史观看 sync with the account;
/// 本地列表 is local only.
struct MyView: View {
    @Environment(AccountStore.self) private var store
    @Environment(WatchLaterStore.self) private var watchLater
    @Environment(LocalLibrary.self) private var library
    @State private var showingLogin = false
    @State private var confirmingLogout = false

    var body: some View {
        List {
            Section { accountHeader }

            Section {
                NavigationLink(value: Route.watchLater) {
                    LabeledContent {
                        if watchLater.loaded { Text("\(watchLater.totalCount)") }
                    } label: {
                        Label("稍后观看", systemImage: "clock")
                    }
                }
                NavigationLink(value: Route.history) {
                    Label("历史观看", systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                NavigationLink(value: Route.localList) {
                    LabeledContent {
                        Text("\(library.items.count)")
                    } label: {
                        Label("本地列表", systemImage: "star")
                    }
                }
            }

            // No explanatory footers under rows (the user's rule).
            Section {
                if store.isLoggedIn {
                    NavigationLink(value: Route.accountSettings) {
                        Label("账户设置", systemImage: "person.text.rectangle")
                    }
                }
                NavigationLink(value: Route.appSettings) {
                    Label("应用设置", systemImage: "gearshape")
                }
            }

            if store.isLoggedIn {
                Section {
                    Button("退出登录", role: .destructive) { confirmingLogout = true }
                }
            }
        }
        .navigationTitle("我的")
        .refreshable {
            await store.refresh()
            await watchLater.reload(store.client)
        }
        .task(id: store.client.userSession) { await watchLater.loadIfNeeded(store.client) }
        // Every time 我的 shows (e.g. back from 账户设置 after changing the avatar).
        .onAppear { Task { await store.refresh() } }
        .confirmationDialog("退出登录？", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { store.logOut() }
        }
        .sheet(isPresented: $showingLogin) { loginSheet }
    }

    @ViewBuilder private var accountHeader: some View {
        if let account = store.account {
            HStack(spacing: 14) {
                AsyncImage(url: account.iconURL) { $0.resizable() } placeholder: { Color.secondary.opacity(0.2) }
                    .frame(width: 60, height: 60)
                    .clipShape(.circle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.nickname).font(.title3.bold())
                    Text(account.isPremium ? "高级会员" : "普通会员")
                        .font(.subheadline)
                        .foregroundStyle(account.isPremium ? .orange : .secondary)
                    Text("ID \(account.id)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } else if store.isLoggedIn {
            // Logged in, profile not loaded yet (checking, or offline).
            if store.isChecking {
                HStack { ProgressView(); Text("正在确认登录状态…") }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = store.lastError { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button("重新加载账号信息") { Task { await store.refresh() } }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未登录").font(.title3.bold())
                        Text("登录后可看个性化推荐、关注、稍后观看和历史").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("登录 Niconico") { showingLogin = true }
                    .buttonStyle(.borderedProminent)
                if let error = store.lastError {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var loginSheet: some View {
        NavigationStack {
            LoginWebView { session in
                showingLogin = false
                Task { await store.logIn(userSession: session) }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("登录 Niconico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingLogin = false }
                }
            }
        }
    }
}

/// Shown on pages that need an account when logged out.
struct LoginRequiredView: View {
    let feature: String

    var body: some View {
        ContentUnavailableView(
            "需要登录", systemImage: "person.crop.circle.badge.questionmark",
            description: Text("\(L(feature))需要登录 Niconico。请到「我的」页面登录。")
        )
    }
}
