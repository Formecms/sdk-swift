import Foundation

/// Response envelope returned by every SDK call that hits the network.
///
/// `value` is the decoded payload. `etag` is the server's strong ETag when
/// present (used for optimistic concurrency on a subsequent `PATCH`/`PUT`).
/// `status` is the HTTP status code. `headers` is the full response header
/// map with lowercased keys for case-insensitive lookup.
///
/// Mirror of the TypeScript SDK's `ApiResponse<T>` shape so callers moving
/// between SDKs find the same mental model.
///
/// Typical use:
///
/// ```swift
/// let response = try await client.entries.get(id: "...")
/// let entry = response.value
/// let etag  = response.etag           // strong ETag, e.g. "\"5\""
///
/// // Pass it back on the next write to detect concurrent edits:
/// let updated = try await client.entries.patch(
///     id: entry.id,
///     PatchEntryInput(fields: ["slug": .string("v2")]),
///     ifMatch: etag
/// )
/// ```
public struct FormeResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let etag: String?
    public let status: Int
    public let headers: [String: String]

    public init(value: Value, etag: String?, status: Int, headers: [String: String]) {
        self.value = value
        self.etag = etag
        self.status = status
        self.headers = headers
    }

    /// Transform the wrapped value while preserving response metadata.
    /// Useful when a namespace method needs to convert from a wire envelope
    /// (e.g. `ManagementList<T>`) to a public type (e.g. `PaginatedList<T>`).
    public func map<NewValue: Sendable>(
        _ transform: (Value) -> NewValue
    ) -> FormeResponse<NewValue> {
        FormeResponse<NewValue>(
            value: transform(value),
            etag: etag,
            status: status,
            headers: headers
        )
    }
}
