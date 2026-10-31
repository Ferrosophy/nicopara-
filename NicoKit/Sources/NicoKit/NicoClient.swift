import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to Niconico directly from the device.
///
/// Cookies are always explicit: the session never stores or sends cookies on its own, so a
/// request carries exactly the login cookie given here (or none, as a guest).
public struct NicoClient: Sendable {
    static let baseURL = "https://www.nicovideo.jp"
    static let frontendHeaders = [
        "X-Frontend-ID": "6",
        "X-Frontend-Version": "0",
    ]

    public static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    private let session: URLSession
    /// Value of the `user_session` cookie after logging in; nil for a guest.
    public let userSession: String?

    public init(userSession: String? = nil, session: URLSession = NicoClient.sharedSession) {
        self.userSession = userSession
        self.session = session
    }

    public var isLoggedIn: Bool { userSession != nil }

    func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        for (field, value) in Self.frontendHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let userSession {
            request.setValue("user_session=\(userSession)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    func sendRaw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, response as? HTTPURLResponse)
        } catch {
            throw NicoError.network(error.localizedDescription)
        }
    }

    /// Maps a body that is not the expected JSON to an HTTP error when the status explains it.
    private func parse<T>(_ response: HTTPURLResponse?, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch NicoError.decoding(let detail) {
            if let status = response?.statusCode, !(200..<300).contains(status) {
                throw NicoError.http(status: status)
            }
            throw NicoError.decoding(detail)
        }
    }

    // MARK: - Video

    public func videoInfo(_ id: VideoID) async throws -> VideoInfo {
        let trackID = "AAAAAAAAAA_\(Int(Date().timeIntervalSince1970 * 1000))"
        let path = isLoggedIn ? "v3" : "v3_guest"
        let url = URL(string: "\(Self.baseURL)/api/watch/\(path)/\(id.rawValue)?actionTrackId=\(trackID)")!
        let (data, response) = try await send(request(url))
        // Error bodies (400/404 with meta.errorCode) are parsed too, for a precise message.
        return try parse(response) { try VideoInfo.parse(watchResponse: data) }
    }

    /// Requests an HLS session for a video fetched with ``videoInfo(_:)``.
    /// The result expires after a while (about a day); request a new one per playback.
    public func hlsPlayback(for info: VideoInfo, selection: HLSSelection = .automatic) async throws -> HLSPlayback {
        let outputs = HLSPlayback.outputs(for: info, selection: selection)
        guard let accessRightKey = info.accessRightKey, let trackID = info.watchTrackID, !outputs.isEmpty else {
            throw NicoError.notPlayable
        }

        let url = URL(string: "https://nvapi.nicovideo.jp/v1/watch/\(info.id.rawValue)/access-rights/hls?actionTrackId=\(trackID)")!
        var request = request(url, method: "POST")
        request.httpBody = try JSONEncoder().encode(["outputs": outputs])
        request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accessRightKey, forHTTPHeaderField: "X-Access-Right-Key")
        request.setValue(Self.baseURL, forHTTPHeaderField: "X-Request-With")

        let (data, response) = try await send(request)
        let headers = (response?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { result, field in
            if let key = field.key as? String, let value = field.value as? String { result[key] = value }
        }
        return try parse(response) {
            try HLSPlayback.parse(accessRightsResponse: data, headers: headers, url: url)
        }
    }

    /// GET an nvapi URL and parse the body.
    func getNVAPI<T>(_ url: URL, _ decode: (Data) throws -> T) async throws -> T {
        let (data, response) = try await send(request(url))
        return try parse(response) { try decode(data) }
    }

    // MARK: - Account

    /// The logged-in user. Throws `NicoError.api(errorCode: "UNAUTHORIZED", …)` when the
    /// login cookie is missing or expired.
    public func me() async throws -> Account {
        try await getNVAPI(URL(string: "https://nvapi.nicovideo.jp/v1/users/me")!) { try Account.parse($0) }
    }
}

extension NicoError {
    /// True when the login cookie was rejected and the user has to log in again.
    public var isUnauthorized: Bool {
        if case .api("UNAUTHORIZED", _) = self { true } else { false }
    }
}
