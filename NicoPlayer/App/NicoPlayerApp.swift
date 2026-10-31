import AVFoundation
import SwiftUI

@main
struct NicoPlayerApp: App {
    // Decides allowed orientations: portrait, or landscape while the player is fullscreen.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = Router()
    @State private var account = AccountStore()
    @State private var feed = FeedStore()
    @State private var follow = FollowStore()
    @State private var watchLater = WatchLaterStore()
    @State private var library = LocalLibrary()
    @State private var settings = AppSettings()
    @State private var translator = TranslationStore()
    @State private var listen = ListenStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Localization.install(AppSettings.storedLanguage)
        // Play sound even when the ring/silent switch is on silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            @Bindable var router = router
            @Bindable var listen = listen
            TabView(selection: $router.tab) {
                Tab("首页", systemImage: "house", value: Router.Tab.feed) {
                    NavigationStack(path: $router.feedPath) { HomeView().nicoDestinations() }
                        .environment(\.currentTab, .feed)
                }
                Tab("关注", systemImage: "heart.text.square", value: Router.Tab.follow) {
                    NavigationStack(path: $router.followPath) { FollowView().nicoDestinations() }
                        .environment(\.currentTab, .follow)
                }
                Tab("我的", systemImage: "person.crop.circle", value: Router.Tab.me) {
                    NavigationStack(path: $router.mePath) { MyView().nicoDestinations() }
                        .environment(\.currentTab, .me)
                }
            }
            // 听视频: the page full screen; when closed while playing, a small bar above the tabs.
            .overlay(alignment: .bottom) {
                ListenMiniBar().padding(.bottom, 74)
            }
            .fullScreenCover(isPresented: $listen.isPresented) {
                ListenView().tint(settings.accentColor)
            }
            // The stores go on last so everything above (tabs, mini bar, covers) can see them.
            .environment(router)
            .environment(account)
            .environment(feed)
            .environment(follow)
            .environment(watchLater)
            .environment(library)
            .environment(settings)
            .environment(translator)
            .environment(listen)
            .tint(settings.accentColor)
            .environment(\.locale, Locale(identifier: settings.language.rawValue))
            // Rebuild every screen in the new language.
            .id(settings.language)
            .task { await account.refresh() }
            // Back from the background (e.g. after changing the avatar on the website): reload
            // the account so 我的 shows the new nickname / avatar.
            .onChange(of: scenePhase) { if scenePhase == .active { Task { await account.refresh() } } }
        }
    }
}
