import Foundation

/// Environment CRUD (Management API).
public struct EnvironmentNamespace: Sendable {
    let client: FormeClient

    private struct EnvelopeUnpaginated: Decodable {
        let data: [Environment]
    }

    public func list() async throws -> [Environment] {
        let envelope: EnvelopeUnpaginated = try await client.executor.get("/management/environments")
        return envelope.data
    }

    public func get(id: String) async throws -> Environment {
        try await client.executor.get("/management/environments/\(id)")
    }

    public func create(_ input: CreateEnvironmentInput) async throws -> Environment {
        try await client.executor.post("/management/environments", body: input)
    }

    public func update(id: String, _ input: UpdateEnvironmentInput) async throws -> Environment {
        try await client.executor.put("/management/environments/\(id)", body: input)
    }

    public func delete(id: String) async throws {
        try await client.executor.delete("/management/environments/\(id)")
    }
}
