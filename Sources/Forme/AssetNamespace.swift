import Foundation

/// Asset operations. File upload uses `Data` + filename + MIME type;
/// multipart body is constructed internally per RFC 7578.
public struct AssetNamespace: Sendable {
    let client: FormeClient

    // MARK: - Management API

    public func list(
        limit: Int = 25,
        offset: Int = 0,
        status: String? = nil,
        locale: String? = nil
    ) async throws -> FormeResponse<PaginatedList<Asset>> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let status = status { params["status"] = .string(status) }
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }

        return try await client.executor.get(
            "/management/assets\(buildQuery(params))"
        )
    }

    public func get(id: String, locale: String? = nil) async throws -> FormeResponse<Asset> {
        var params: [String: QueryValue] = [:]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        return try await client.executor.get("/management/assets/\(encodePathComponent(id))\(buildQuery(params))")
    }

    /// Upload a new asset (Management API). The file bytes plus optional
    /// metadata fields are wrapped in a `multipart/form-data` request.
    ///
    /// - Parameters:
    ///   - data: Raw bytes of the file (e.g. UIImage data, video bytes, PDF).
    ///   - filename: Filename including extension. The server uses this for
    ///     content sniffing and storage.
    ///   - mimeType: Content type (e.g. `image/jpeg`, `video/mp4`,
    ///     `application/pdf`).
    ///   - title: Optional human-readable title.
    ///   - description: Optional description.
    ///   - alt: Optional alt text (image accessibility).
    public func upload(
        data: Data,
        filename: String,
        mimeType: String,
        title: String? = nil,
        description: String? = nil,
        alt: String? = nil
    ) async throws -> FormeResponse<Asset> {
        var parts: [MultipartPart] = [
            .file(name: "file", filename: filename, mimeType: mimeType, data: data),
        ]
        if let title = title { parts.append(.text(name: "title", value: title)) }
        if let description = description { parts.append(.text(name: "description", value: description)) }
        if let alt = alt { parts.append(.text(name: "alt", value: alt)) }

        let body = MultipartFormData(parts: parts)
        return try await client.executor.sendRaw(
            method: "POST",
            path: "/management/assets",
            body: body.body,
            contentType: body.contentType
        )
    }

    /// Replace the underlying file of an existing asset, keeping its id and
    /// metadata. Server bumps `draft_version`. Pass `ifMatch` for optimistic
    /// concurrency.
    public func replaceFile(
        id: String,
        data: Data,
        filename: String,
        mimeType: String,
        ifMatch: String? = nil
    ) async throws -> FormeResponse<Asset> {
        let body = MultipartFormData(parts: [
            .file(name: "file", filename: filename, mimeType: mimeType, data: data),
        ])
        var headers: [String: String] = [:]
        if let ifMatch = ifMatch { headers["If-Match"] = ifMatch }
        return try await client.executor.sendRaw(
            method: "POST",
            path: "/management/assets/\(encodePathComponent(id))/file",
            body: body.body,
            contentType: body.contentType,
            extraHeaders: headers
        )
    }

    /// Download the binary file behind an asset. Returns the raw bytes plus
    /// response metadata (status, headers). Bypasses JSON decoding.
    public func downloadFile(id: String) async throws -> FormeResponse<Data> {
        try await client.executor.download("/management/assets/\(encodePathComponent(id))/file")
    }

    /// Update asset metadata (PUT — replaces only the provided fields; omitted fields are preserved).
    /// Pass `ifMatch` with an ETag from a prior response for optimistic concurrency.
    public func update(
        id: String,
        _ input: UpdateAssetInput,
        ifMatch: String? = nil
    ) async throws -> FormeResponse<Asset> {
        try await client.executor.put(
            "/management/assets/\(encodePathComponent(id))",
            body: input,
            ifMatch: ifMatch
        )
    }

    /// Patch asset metadata (same semantics as PUT for assets plus If-Match concurrency).
    public func patch(
        id: String,
        _ input: UpdateAssetInput,
        ifMatch: String? = nil
    ) async throws -> FormeResponse<Asset> {
        try await client.executor.patch(
            "/management/assets/\(encodePathComponent(id))",
            body: input,
            ifMatch: ifMatch
        )
    }

    public func delete(id: String) async throws {
        try await client.executor.delete("/management/assets/\(encodePathComponent(id))")
    }

    public func publish(id: String) async throws -> FormeResponse<Asset> {
        try await client.executor.postEmpty("/management/assets/\(encodePathComponent(id))/publish")
    }

    public func unpublish(id: String) async throws -> FormeResponse<Asset> {
        try await client.executor.postEmpty("/management/assets/\(encodePathComponent(id))/unpublish")
    }

    /// List version snapshots for an asset (Management API).
    public func versions(
        id: String,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> FormeResponse<PaginatedList<AssetVersion>> {
        let params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        return try await client.executor.get(
            "/management/assets/\(encodePathComponent(id))/versions\(buildQuery(params))"
        )
    }

    // MARK: - Delivery API

    public func listDelivery(
        limit: Int = 25,
        offset: Int = 0,
        locale: String? = nil
    ) async throws -> FormeResponse<PaginatedList<Asset>> {
        var params: [String: QueryValue] = [
            "limit": .int(limit),
            "offset": .int(offset),
        ]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        return try await client.executor.get("/delivery/assets\(buildQuery(params))")
    }

    public func getDelivery(id: String, locale: String? = nil) async throws -> FormeResponse<Asset> {
        var params: [String: QueryValue] = [:]
        if let loc = locale ?? client.configuration.defaultLocale { params["locale"] = .string(loc) }
        return try await client.executor.get("/delivery/assets/\(encodePathComponent(id))\(buildQuery(params))")
    }

    /// Construct the public download URL for an asset's binary file
    /// (Delivery API). Pure URL builder — no network call.
    ///
    /// `baseURL` defaults to the client's configured `baseURL`, which is
    /// only correct when the client is configured against the **Delivery**
    /// host (e.g. `https://delivery.forme.sh`). If the client is configured
    /// against the Management host, pass the delivery host explicitly:
    ///
    /// ```swift
    /// // Idiomatic — separate clients per host:
    /// let url = delivery.assets.fileUrl(id: assetId)
    ///
    /// // Or, when working from a single management-configured client:
    /// let url = mgmt.assets.fileUrl(
    ///     id: assetId,
    ///     baseURL: URL(string: "https://delivery.forme.sh")!
    /// )
    /// ```
    ///
    /// Use this when rendering an `<img>`-style URL in a UI; use
    /// `downloadFile(id:)` (Management API) when you need the raw bytes
    /// in-process.
    public func fileUrl(id: String, baseURL: URL? = nil) -> URL {
        let host = baseURL ?? client.configuration.baseURL
        return host.appendingRelative(
            "/delivery/assets/\(encodePathComponent(id))/file"
        )
    }
}
