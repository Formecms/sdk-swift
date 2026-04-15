import Foundation

/// Custom ISO 8601 decoding strategy that accepts both fractional seconds
/// (e.g., `"2026-04-14T10:30:00.123Z"`) and standard form
/// (e.g., `"2026-04-14T10:30:00Z"`).
///
/// Foundation's built-in `.iso8601` strategy rejects fractional seconds —
/// a classic gotcha that silently breaks CMS SDKs when the server includes
/// millisecond precision. The Forme API uses `timestamptz::text` in Postgres,
/// which typically emits microsecond precision, so this shim is required.
enum FormeDateCoding {
    // `ISO8601DateFormatter` is not retroactively `Sendable`, but its
    // parse/format methods are documented thread-safe once configured
    // (it wraps an immutable `CFDateFormatter`). `nonisolated(unsafe)`
    // tells the compiler "I have audited this; sharing is safe."

    /// ISO 8601 formatter for dates WITH fractional seconds (primary form).
    nonisolated(unsafe) static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO 8601 formatter for dates WITHOUT fractional seconds (fallback).
    nonisolated(unsafe) static let withoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Decode a JSON string into a `Date`, accepting both fractional and
    /// non-fractional ISO 8601 formats.
    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = withFractional.date(from: string) ?? withoutFractional.date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO 8601 date: \(string)"
        )
    }

    /// Encode a `Date` as ISO 8601 with fractional seconds.
    static func encode(_ date: Date, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(withFractional.string(from: date))
    }
}

/// Produce a `JSONDecoder` preconfigured for Forme API responses.
///
/// Uses `FormeDateCoding` for `Date` decoding. `keyDecodingStrategy` is
/// `.useDefaultKeys` because the API is camelCase end-to-end — no
/// snake_case/camelCase transformation needed.
///
/// Each call returns a fresh decoder to keep the closure-based strategies
/// `Sendable` under strict concurrency. `JSONDecoder` is cheap to construct.
func makeFormeDecoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder in
        try FormeDateCoding.decode(decoder)
    }
    return d
}

/// Produce a `JSONEncoder` preconfigured for Forme API requests.
func makeFormeEncoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .custom { date, encoder in
        try FormeDateCoding.encode(date, to: encoder)
    }
    return e
}
