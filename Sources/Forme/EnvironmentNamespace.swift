import Foundation

/// Environment CRUD (Management API).
public struct EnvironmentNamespace: Sendable {
    let client: FormeClient

    public func list() async throws -> FormeResponse<[Environment]> {
        let response: FormeResponse<PaginatedList<Environment>> =
            try await client.executor.get("/management/environments")
        return response.map(\.items)
    }

    public func get(id: String) async throws -> FormeResponse<Environment> {
        try await client.executor.get("/management/environments/\(encodePathComponent(id))")
    }

    public func create(_ input: CreateEnvironmentInput) async throws -> FormeResponse<Environment> {
        try await client.executor.post("/management/environments", body: input)
    }

    public func update(
        id: String,
        _ input: UpdateEnvironmentInput
    ) async throws -> FormeResponse<Environment> {
        try await client.executor.put(
            "/management/environments/\(encodePathComponent(id))",
            body: input
        )
    }

    public func delete(id: String) async throws {
        try await client.executor.delete("/management/environments/\(encodePathComponent(id))")
    }
}
