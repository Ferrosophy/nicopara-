import Foundation

/// Responses from nvapi.nicovideo.jp share one envelope: `{"meta": {"status", "errorCode"}, "data": …}`.
enum NVAPI {
    private struct Meta: Decodable {
        var status: Int
        var errorCode: String?
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        var meta: Meta
        var data: Payload?
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder.nico.decode(Envelope<T>.self, from: data)
        } catch {
            throw NicoError.decoding(String(describing: error))
        }
        guard (200..<300).contains(envelope.meta.status) else {
            throw NicoError.api(errorCode: envelope.meta.errorCode ?? "UNKNOWN", reasonCode: nil)
        }
        guard let payload = envelope.data else {
            throw NicoError.decoding("missing data")
        }
        return payload
    }

    /// Checks only `meta.status`, for write calls whose `data` we do not need.
    @discardableResult
    static func decodeStatus(from data: Data) throws -> Int {
        struct StatusOnly: Decodable { var meta: Meta }
        let envelope: StatusOnly
        do {
            envelope = try JSONDecoder.nico.decode(StatusOnly.self, from: data)
        } catch {
            throw NicoError.decoding(String(describing: error))
        }
        guard (200..<300).contains(envelope.meta.status) else {
            throw NicoError.api(errorCode: envelope.meta.errorCode ?? "UNKNOWN", reasonCode: nil)
        }
        return envelope.meta.status
    }
}

/// Decodes `T`, or nil if that fails, so an optional extra cannot fail its parent.
struct Lenient<T: Decodable>: Decodable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// IDs arrive as numbers for users (`4`) and strings for channels (`"ch2632720"`).
struct LooseID: Decodable, Sendable, Equatable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = String(int)
        } else {
            value = try container.decode(String.self)
        }
    }
}
