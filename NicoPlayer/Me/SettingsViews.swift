import NicoKit
import SwiftUI
import WebKit

/// 账户设置: the website's own account settings, opened inside the app already logged in
/// (the session cookie is put into a throwaway web store first).
struct AccountSettingsView: View {
    static let url = URL(string: "https://account.nicovideo.jp/my/account")!

    @Environment(AccountStore.self) private var account

    var body: some View {
        Group {
            if let session = account.client.userSession {
                LoggedInWebView(url: Self.url, userSession: session)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                LoginRequiredView(feature: "账户设置")
            }
        }
        .navigationTitle("账户设置")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { Task { await account.refresh() } }
    }
}

/// A web page with the Niconico login cookie set, in a non-persistent store.
struct LoggedInWebView: UIViewRepresentable {
    let url: URL
    let userSession: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        let cookie = HTTPCookie(properties: [
            .name: "user_session", .value: userSession, .domain: ".nicovideo.jp", .path: "/", .secure: "TRUE",
        ])
        let request = URLRequest(url: url)
        if let cookie {
            configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { webView.load(request) }
        } else {
            webView.load(request)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

