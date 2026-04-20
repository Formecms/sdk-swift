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
    ) async throws -> FormeResponse<PaginatedList<Entry>> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let cmId = contentModelId { params["contentModelId"] = .string(cmId) }
        if let status = status { params["status"] = .string(status) }
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        if let fields = fields { params["fields"] = .fields(fields) }

        let response: FormeResponse<PaginatedList<Entry>> = try await client.executor.get(
            "/management/entries\(buildQuery(params))"
        )
        return response
    }

    /// Get a single entry by id (Management API).
    public func get(id: String, locale: String? = nil) async throws -> FormeResponse<Entry> {
        var params: [String: QueryValue] = [:]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        return try await client.executor.get("/management/entries/\(encodePathComponent(id))\(buildQuery(params))")
    }

    /// Create a new entry (Management API).
    public func create(_ input: CreateEntryInput) async throws -> FormeResponse<Entry> {
        try await client.executor.post("/management/entries", body: input)
    }

    /// Fully replace an entry's fields (PUT). For partial updates prefer `patch(...)`.
    /// Pass `ifMatch` with an ETag from a prior response for optimistic concurrency.
    public func update(
        id: String,
        _ input: UpdateEntryInput,
        ifMatch: String? = nil
    ) async throws -> FormeResponse<Entry> {
        try await client.executor.put(
            "/management/entries/\(encodePathComponent(id))",
            body: input,
            ifMatch: ifMatch
        )
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
    ) async throws -> FormeResponse<Entry> {
        var params: [String: QueryValue] = [:]
        if let loc = locale { params["locale"] = .string(loc) }
        return try await client.executor.patch(
            "/management/entries/\(encodePathComponent(id))\(buildQuery(params))",
            body: input,
            ifMatch: ifMatch
        )
    }

    /// Delete an entry (Management API).
    public func delete(id: String) async throws {
        try await client.executor.delete("/management/entries/\(encodePathComponent(id))")
    }

    /// Publish an entry (Management API).
    public func publish(id: String) async throws -> FormeResponse<Entry> {
        try await client.executor.postEmpty("/management/entries/\(encodePathComponent(id))/publish")
    }

    /// Unpublish an entry (Management API).
    public func unpublish(id: String) async throws -> FormeResponse<Entry> {
        try await client.executor.postEmpty("/management/entries/\(encodePathComponent(id))/unpublish")
    }

    /// List version snapshots for an entry (Management API).
    /// Each version is a frozen copy of the entry's fields at publish time.
    public func versions(
        id: String,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> FormeResponse<PaginatedList<EntryVersion>> {
        let params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        return try await client.executor.get(
            "/management/entries/\(encodePathComponent(id))/versions\(buildQuery(params))"
        )
    }

    /// Intelligent Actions sub-namespace.
    public var actions: EntryActionsNamespace { EntryActionsNamespace(client: client) }

    // MARK: - Delivery API

    /// List published entries (Delivery API).
    ///
    /// When `include` is `>= 1`, the response includes the `includes` payload
    /// with linked entries and assets — see `DeliveryListResponse.includes`.
    public func listDelivery(
        contentModelId: String? = nil,
        locale: String? = nil,
        fields: [String: FieldFilter]? = nil,
        include: Int? = nil,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> FormeResponse<DeliveryEntryListResponse> {
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
    ///
    /// When `include` is `>= 1`, the response includes the `includes` payload
    /// with linked entries and assets.
    public func getDelivery(
        id: String,
        locale: String? = nil,
        include: Int? = nil
    ) async throws -> FormeResponse<DeliveryEntryResponse> {
        var params: [String: QueryValue] = [:]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        if let include = include { params["include"] = .int(include) }
        return try await client.executor.get("/delivery/entries/\(encodePathComponent(id))\(buildQuery(params))")
    }
}
