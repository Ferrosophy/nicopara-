import NicoKit
import Observation
import SwiftUI

/// Tabs and their navigation stacks, owned by the app so the video page's ⌂ button can
/// close every pushed page and jump to 推荐 (Bilibili's "home" button).
@MainActor @Observable
final class Router {
    enum Tab: Hashable { case feed, follow, me }

    var tab: Tab = .feed
    var feedPath = NavigationPath()
    var followPath = NavigationPath()
    var mePath = NavigationPath()

    /// ⌂: empty the stack the user is in and the 推荐 stack, then show 推荐.
    func goHome(from origin: Tab) {
        switch origin {
        case .feed: break
        case .follow: followPath = NavigationPath()
        case .me: mePath = NavigationPath()
        }
        feedPath = NavigationPath()
        tab = .feed
    }

    func push(_ value: some Hashable, in tab: Tab) {
        switch tab {
        case .feed: feedPath.append(value)
        case .follow: followPath.append(value)
        case .me: mePath.append(value)
        }
    }
}

/// Pages reached by value, besides `VideoID`, `NicoUser` and `SearchQuery`.
enum Route: Hashable {
    case search
    case watchLater
    case history
    case localList
    case series(SeriesRef, current: VideoID?)
    case accountSettings
    case appSettings
    case genre(RankingGenre)
}

extension EnvironmentValues {
    /// Which tab's stack a view is in, for ⌂ and for pushing.
    @Entry var currentTab: Router.Tab = .feed
}

extension View {
    /// Where links inside any tab lead.
    func nicoDestinations() -> some View {
        navigationDestination(for: VideoID.self) { VideoPage(id: $0) }
            .navigationDestination(for: NicoUser.self) { UserPageView(user: $0) }
            .navigationDestination(for: SearchQuery.self) { query in
                SearchResultsView(initial: query)
                    .navigationTitle(query.mode == .tag ? "#\(query.text)" : query.text)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .search: SearchScreen()
                case .watchLater: WatchLaterView()
                case .history: HistoryView()
                case .localList: LocalListView()
                case .series(let series, let current): SeriesView(series: series, current: current)
                case .accountSettings: AccountSettingsView()
                case .appSettings: AppSettingsView()
                case .genre(let genre): GenreRankingView(genre: genre)
                }
            }
    }
}
