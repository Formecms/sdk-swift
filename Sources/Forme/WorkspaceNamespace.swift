import Foundation

/// Workspace operations (Management API only).
public struct WorkspaceNamespace: Sendable {
    let client: FormeClient

    /// Get the workspace for the current API key.
    public func get() async throws -> FormeResponse<Workspace> {
        try await client.executor.get("/management/workspace")
    }

    /// Update the workspace (name only for now).
    public func update(name: String) async throws -> FormeResponse<Workspace> {
        try await client.executor.put(
            "/management/workspace",
            body: UpdateWorkspaceInput(name: name)
        )
    }

    /// Get aggregated AI usage stats for the workspace.
    public func aiUsage() async throws -> FormeResponse<AiUsageStats> {
        try await client.executor.get("/management/workspace/ai-usage")
    }
}
