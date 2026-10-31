import Foundation
import Testing
@testable import NicoKit

@Suite struct AccountTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    // `users/4` has the same user object as `users/me`; captured 2026-10-30.
    @Test func parsesUser() throws {
        let account = try Account.parse(fixture("user-4"))
        #expect(account == Account(
            id: "4", nickname: "中の",
            iconURL: URL(string: "https://img.nicoprofile.nimg.jp/usericon/defaults/blank.jpg"),
            isPremium: false
        ))
    }

    @Test func unauthorized() throws {
        #expect {
            try Account.parse(fixture("users-me-unauthorized"))
        } throws: { error in
            (error as? NicoError)?.isUnauthorized == true
        }
        #expect(NicoError.api(errorCode: "UNAUTHORIZED", reasonCode: nil).errorDescription == "登录已失效，需要重新登录")
    }

    @Test func guestRequestHasNoCookie() {
        let request = NicoClient().request(URL(string: "https://nvapi.nicovideo.jp/v1/users/me")!)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Frontend-ID") == "6")
    }

    @Test func loggedInRequestSendsSessionCookie() {
        let client = NicoClient(userSession: "user_session_123_abc")
        let request = client.request(URL(string: "https://nvapi.nicovideo.jp/v1/users/me")!)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "user_session=user_session_123_abc")
        #expect(client.isLoggedIn)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["NICO_LIVE"] == "1"))
struct LiveAccountTests {
    @Test func guestIsUnauthorized() async {
        await #expect {
            try await NicoClient().me()
        } throws: { error in
            (error as? NicoError)?.isUnauthorized == true
        }
    }

    /// A made-up session cookie must be rejected the same way, so the app can log out cleanly.
    @Test func bogusSessionIsUnauthorized() async {
        await #expect {
            try await NicoClient(userSession: "user_session_0_invalid").me()
        } throws: { error in
            (error as? NicoError)?.isUnauthorized == true
        }
    }
}
