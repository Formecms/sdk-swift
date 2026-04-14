import Foundation

/// Locale CRUD (Management API) + read (Delivery API).
public struct LocaleNamespace: Sendable {
    let client: FormeClient

    private struct EnvelopeUnpaginated: Decodable {
        let data: [Locale]
    }

    // MARK: - Management API

    public func list() async throws -> [Locale] {
        let envelope: EnvelopeUnpaginated = try await client.executor.get("/management/locales")
        return envelope.data
    }

    public func get(id: String) async throws -> Locale {
        try await client.executor.get("/management/locales/\(id)")
    }

    public func create(_ input: CreateLocaleInput) async throws -> Locale {
        try await client.executor.post("/management/locales", body: input)
    }

    public func update(id: String, _ input: UpdateLocaleInput) async throws -> Locale {
        try await client.executor.put("/management/locales/\(id)", body: input)
    }

    public func delete(id: String) async throws {
        try await client.executor.delete("/management/locales/\(id)")
    }

    // MARK: - Delivery API

    public func listDelivery() async throws -> [Locale] {
        let envelope: EnvelopeUnpaginated = try await client.executor.get("/delivery/locales")
        return envelope.data
    }
}
