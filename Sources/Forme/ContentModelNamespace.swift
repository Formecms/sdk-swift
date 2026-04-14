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
    ) async throws -> PaginatedListMgmt<ContentModel> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let apiId = apiId { params["apiId"] = .string(apiId) }
        let envelope: ManagementList<ContentModel> = try await client.executor.get(
            "/management/content-models\(buildQuery(params))"
        )
        return envelope.toPaginated()
    }

    public func get(id: String) async throws -> ContentModel {
        try await client.executor.get("/management/content-models/\(id)")
    }

    public func create(_ input: CreateContentModelInput) async throws -> ContentModel {
        try await client.executor.post("/management/content-models", body: input)
    }

    public func update(id: String, _ input: UpdateContentModelInput) async throws -> ContentModel {
        try await client.executor.put("/management/content-models/\(id)", body: input)
    }

    public func delete(id: String) async throws {
        try await client.executor.delete("/management/content-models/\(id)")
    }

    // MARK: - Delivery API

    public func listDelivery(
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> PaginatedList<ContentModel> {
        let params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        return try await client.executor.get("/delivery/content-models\(buildQuery(params))")
    }

    public func getDelivery(id: String) async throws -> ContentModel {
        try await client.executor.get("/delivery/content-models/\(id)")
    }
}
