import Foundation

/// Asset operations. File upload uses `Data` + filename + MIME type;
/// multipart body is constructed internally.
public struct AssetNamespace: Sendable {
    let client: FormeClient

    // MARK: - Management API

    public func list(
        limit: Int = 25,
        offset: Int = 0,
        status: String? = nil,
        locale: String? = nil
    ) async throws -> PaginatedListMgmt<Asset> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let status = status { params["status"] = .string(status) }
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }

        let envelope: ManagementList<Asset> = try await client.executor.get(
            "/management/assets\(buildQuery(params))"
        )
        return envelope.toPaginated()
    }

    public func get(id: String, locale: String? = nil) async throws -> Asset {
        var params: [String: QueryValue] = [:]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        return try await client.executor.get("/management/assets/\(id)\(buildQuery(params))")
    }

    /// Update asset metadata (PUT — replaces only the provided fields; omitted fields are preserved).
    public func update(id: String, _ input: UpdateAssetInput) async throws -> Asset {
        try await client.executor.put("/management/assets/\(id)", body: input)
    }

    /// Patch asset metadata (same semantics as PUT for assets plus If-Match concurrency).
    public func patch(
        id: String,
        _ input: UpdateAssetInput,
        ifMatch: String? = nil
    ) async throws -> Asset {
        try await client.executor.patch(
            "/management/assets/\(id)",
            body: input,
            ifMatch: ifMatch
        )
    }

    public func delete(id: String) async throws {
        try await client.executor.delete("/management/assets/\(id)")
    }

    public func publish(id: String) async throws -> Asset {
        try await client.executor.postEmpty("/management/assets/\(id)/publish")
    }

    public func unpublish(id: String) async throws -> Asset {
        try await client.executor.postEmpty("/management/assets/\(id)/unpublish")
    }

    // MARK: - Delivery API

    public func listDelivery(
        limit: Int = 25,
        offset: Int = 0,
        locale: String? = nil
    ) async throws -> PaginatedList<Asset> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        return try await client.executor.get("/delivery/assets\(buildQuery(params))")
    }

    public func getDelivery(id: String, locale: String? = nil) async throws -> Asset {
        var params: [String: QueryValue] = [:]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        return try await client.executor.get("/delivery/assets/\(id)\(buildQuery(params))")
    }
}
