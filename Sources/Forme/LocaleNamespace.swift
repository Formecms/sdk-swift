import Foundation

/// Locale CRUD (Management API) + read (Delivery API).
public struct LocaleNamespace: Sendable {
    let client: FormeClient

    // MARK: - Management API

    public func list() async throws -> FormeResponse<[Locale]> {
        let response: FormeResponse<PaginatedList<Locale>> =
            try await client.executor.get("/management/locales")
        return response.map(\.items)
    }

    public func get(id: String) async throws -> FormeResponse<Locale> {
        try await client.executor.get("/management/locales/\(encodePathComponent(id))")
    }

    public func create(_ input: CreateLocaleInput) async throws -> FormeResponse<Locale> {
        try await client.executor.post("/management/locales", body: input)
    }

    public func update(
        id: String,
        _ input: UpdateLocaleInput
    ) async throws -> FormeResponse<Locale> {
        try await client.executor.put(
            "/management/locales/\(encodePathComponent(id))",
            body: input
        )
    }

    public func delete(id: String) async throws {
        try await client.executor.delete("/management/locales/\(encodePathComponent(id))")
    }

    // MARK: - Delivery API

    public func listDelivery() async throws -> FormeResponse<[Locale]> {
        let response: FormeResponse<PaginatedList<Locale>> =
            try await client.executor.get("/delivery/locales")
        return response.map(\.items)
    }
}
