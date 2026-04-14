import Foundation

/// Workspace operations (Management API only).
public struct WorkspaceNamespace: Sendable {
    let client: FormeClient

    /// Get the workspace for the current API key.
    public func get() async throws -> Workspace {
        try await client.executor.get("/management/workspace")
    }

    /// Update the workspace (name only for now).
    public func update(name: String) async throws -> Workspace {
        struct Input: Encodable {
            let name: String
        }
        return try await client.executor.put("/management/workspace", body: Input(name: name))
    }
}
