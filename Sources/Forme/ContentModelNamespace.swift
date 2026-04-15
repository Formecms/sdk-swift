import Foundation

/// Content Model operations. Covers Management API CRUD plus Delivery API
/// read operations.
public struct ContentModelNamespace: Sendable {
    let client: FormeClient

    // MARK: - Management API

    public func list(
        limit: Int = 25,
        offset: Int = 0,
        apiId: String? = nil
    ) async throws -> FormeResponse<PaginatedList<ContentModel>> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let apiId = apiId { params["apiId"] = .string(apiId) }
        return try await client.executor.get(
            "/management/content-models\(buildQuery(params))"
        )
    }

    public func get(id: String) async throws -> FormeResponse<ContentModel> {
        try await client.executor.get("/management/content-models/\(encodePathComponent(id))")
    }

    public func create(_ input: CreateContentModelInput) async throws -> FormeResponse<ContentModel> {
        try await client.executor.post("/management/content-models", body: input)
    }

    public func update(
        id: String,
        _ input: UpdateContentModelInput
    ) async throws -> FormeResponse<ContentModel> {
        try await client.executor.put(
            "/management/content-models/\(encodePathComponent(id))",
            body: input
        )
    }

    public func delete(id: String) async throws {
        try await client.executor.delete("/management/content-models/\(encodePathComponent(id))")
    }

    // MARK: - Delivery API

    public func listDelivery(
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> FormeResponse<PaginatedList<ContentModel>> {
        let params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        return try await client.executor.get("/delivery/content-models\(buildQuery(params))")
    }

    public func getDelivery(id: String) async throws -> FormeResponse<ContentModel> {
        try await client.executor.get("/delivery/content-models/\(encodePathComponent(id))")
    }
}
