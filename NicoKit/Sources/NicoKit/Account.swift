import Foundation

/// The logged-in user, from `nvapi.nicovideo.jp/v1/users/me`.
public struct Account: Sendable, Equatable {
    public var id: String
    public var nickname: String
    public var iconURL: URL?
    public var isPremium: Bool
}

extension Account {
    /// Parses a `users/me` (or `users/{id}`, same shape) response.
    static func parse(_ data: Data) throws -> Account {
        struct User: Decodable {
            struct Icons: Decodable {
                var small: URL?
                var large: URL?
            }
            var id: LooseID
            var nickname: String
            var icons: Icons?
            var isPremium: Bool?
        }
        struct Payload: Decodable { var user: User }

        let user = try NVAPI.decode(Payload.self, from: data).user
        return Account(
            id: user.id.value,
            nickname: user.nickname,
            iconURL: user.icons?.large ?? user.icons?.small,
            isPremium: user.isPremium ?? false
        )
    }
}
