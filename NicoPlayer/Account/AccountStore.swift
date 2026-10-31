import NicoKit
import Observation

/// Login state for the whole app. The `user_session` cookie lives in the keychain;
/// every Niconico request goes through ``client``, which carries it when logged in.
@MainActor @Observable
final class AccountStore {
    private static let keychainKey = "user_session"

    private(set) var client: NicoClient
    private(set) var account: Account?
    /// Set while the stored session is being checked or a fresh login is confirmed.
    private(set) var isChecking = false
    private(set) var lastError: String?

    init() {
        client = NicoClient(userSession: Keychain.string(for: Self.keychainKey))
    }

    var isLoggedIn: Bool { client.isLoggedIn }

    /// Called at launch: confirms the stored session still works and loads the profile.
    func refresh() async {
        guard client.isLoggedIn else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            account = try await client.me()
            lastError = nil
        } catch let error as NicoError where error.isUnauthorized {
            logOut()
            lastError = error.localizedDescription
        } catch {
            // Offline or a server hiccup: keep the session, show the error.
            lastError = error.localizedDescription
        }
    }

    /// Takes the cookie captured from the official login page.
    func logIn(userSession: String) async {
        Keychain.set(userSession, for: Self.keychainKey)
        client = NicoClient(userSession: userSession)
        await refresh()
    }

    func logOut() {
        Keychain.delete(Self.keychainKey)
        client = NicoClient()
        account = nil
    }
}
