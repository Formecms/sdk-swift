import Foundation

/// Entry operations. Works against both Delivery and Management APIs
/// depending on the client's `baseURL` and API key.
public struct EntryNamespace: Sendable {
    let client: FormeClient

    // MARK: - Management API

    /// List entries (Management API).
    public func list(
        contentModelId: String? = nil,
        status: String? = nil,
        locale: String? = nil,
        fields: [String: FieldFilter]? = nil,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> PaginatedListMgmt<Entry> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let cmId = contentModelId { params["contentModelId"] = .string(cmId) }
        if let status = status { params["status"] = .string(status) }
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        if let fields = fields { params["fields"] = .fields(fields) }

        let envelope: ManagementList<Entry> = try await client.executor.get(
            "/management/entries\(buildQuery(params))"
        )
        return envelope.toPaginated()
    }

    /// Get a single entry by id (Management API).
    public func get(id: String, locale: String? = nil) async throws -> Entry {
        var params: [String: QueryValue] = [:]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        return try await client.executor.get("/management/entries/\(id)\(buildQuery(params))")
    }

    /// Create a new entry (Management API).
    public func create(_ input: CreateEntryInput) async throws -> Entry {
        try await client.executor.post("/management/entries", body: input)
    }

    /// Fully replace an entry's fields (PUT). For partial updates prefer `patch(...)`.
    public func update(id: String, _ input: UpdateEntryInput) async throws -> Entry {
        try await client.executor.put("/management/entries/\(id)", body: input)
    }

    /// Partially update an entry's fields (PATCH — shallow merge).
    ///
    /// - Omit a key to preserve its value
    /// - Send `FormeValue.null` to clear the field
    /// - Localized fields merge at the locale key (patching `en-US` preserves `de-DE`)
    /// - Pass `locale: "*"` to replace the whole locale map
    /// - Pass `ifMatch` with an ETag from a prior response for optimistic concurrency
    ///
    /// Throws `FormeError.preconditionFailed` if `ifMatch` is stale.
    public func patch(
        id: String,
        _ input: PatchEntryInput,
        locale: String? = nil,
        ifMatch: String? = nil
    ) async throws -> Entry {
        var params: [String: QueryValue] = [:]
        if let loc = locale { params["locale"] = .string(loc) }
        return try await client.executor.patch(
            "/management/entries/\(id)\(buildQuery(params))",
            body: input,
            ifMatch: ifMatch
        )
    }

    /// Delete an entry (Management API).
    public func delete(id: String) async throws {
        try await client.executor.delete("/management/entries/\(id)")
    }

    /// Publish an entry (Management API).
    public func publish(id: String) async throws -> Entry {
        try await client.executor.postEmpty("/management/entries/\(id)/publish")
    }

    /// Unpublish an entry (Management API).
    public func unpublish(id: String) async throws -> Entry {
        try await client.executor.postEmpty("/management/entries/\(id)/unpublish")
    }

    // MARK: - Delivery API

    /// List published entries (Delivery API).
    public func listDelivery(
        contentModelId: String? = nil,
        locale: String? = nil,
        fields: [String: FieldFilter]? = nil,
        include: Int? = nil,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> PaginatedList<Entry> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let cmId = contentModelId { params["contentModelId"] = .string(cmId) }
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        if let include = include { params["include"] = .int(include) }
        if let fields = fields { params["fields"] = .fields(fields) }

        return try await client.executor.get("/delivery/entries\(buildQuery(params))")
    }

    /// Get a single published entry by id (Delivery API).
    public func getDelivery(
        id: String,
        locale: String? = nil,
        include: Int? = nil
    ) async throws -> Entry {
        var params: [String: QueryValue] = [:]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        if let include = include { params["include"] = .int(include) }
        return try await client.executor.get("/delivery/entries/\(id)\(buildQuery(params))")
    }
}
