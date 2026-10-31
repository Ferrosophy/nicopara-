import SwiftUI
import WebKit

/// Niconico's own login page. The user types their credentials (and 2FA code) there;
/// the app only watches the cookie store for the resulting `user_session` cookie.
struct LoginWebView: UIViewRepresentable {
    static let loginURL = URL(string: "https://account.nicovideo.jp/login?site=niconico&next_url=%2F")!

    let onLogin: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLogin: onLogin) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A fresh, throwaway store per login: nothing from earlier logins leaks in or stays.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        webView.load(URLRequest(url: Self.loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let onLogin: (String) -> Void
        private var done = false

        init(onLogin: @escaping (String) -> Void) {
            self.onLogin = onLogin
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in await check(cookieStore) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { await check(webView.configuration.websiteDataStore.httpCookieStore) }
        }

        private func check(_ store: WKHTTPCookieStore) async {
            guard !done else { return }
            let cookies = await store.allCookies()
            // Logged-out pages may set the cookie to "deleted" to clear it.
            guard let session = cookies.first(where: {
                $0.name == "user_session" && $0.domain.hasSuffix("nicovideo.jp")
                    && !$0.value.isEmpty && $0.value != "deleted"
            }) else { return }
            done = true
            onLogin(session.value)
        }
    }
}
