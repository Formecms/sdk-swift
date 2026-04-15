import Foundation

/// API key management (Management API only).
public struct APIKeyNamespace: Sendable {
    let client: FormeClient

    public struct CreateKeyInput: Sendable, Encodable {
        public let keyType: String
        public let label: String?

        public init(keyType: String, label: String? = nil) {
            self.keyType = keyType
            self.label = label
        }
    }

    /// API key creation response. `plaintextKey` is the unhashed key and is
    /// only returned once at creation time.
    public struct CreatedAPIKey: Sendable, Decodable {
        public let id: String
        public let accountId: String
        public let workspaceId: String
        public let environmentId: String
        public let label: String?
        public let keyType: String
        public let prefix: String
        public let keyHint: String
        public let plaintextKey: String
        public let createdAt: Date
        public let updatedAt: Date
    }

    public func list() async throws -> FormeResponse<[APIKey]> {
        let response: FormeResponse<PaginatedList<APIKey>> =
            try await client.executor.get("/management/api-keys")
        return response.map(\.items)
    }

    public func create(_ input: CreateKeyInput) async throws -> FormeResponse<CreatedAPIKey> {
        try await client.executor.post("/management/api-keys", body: input)
    }

    /// Revoke an API key. The server returns 204 No Content.
    public func revoke(id: String) async throws {
        try await client.executor.delete("/management/api-keys/\(encodePathComponent(id))")
    }
}
