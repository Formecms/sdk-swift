import Foundation

/// Intelligent Actions on entries — rewrite, approve, discard.
///
/// Accessed via `client.entries.actions`:
/// ```swift
/// let result = try await client.entries.actions.rewrite(
///     entryId: "...",
///     input: RewriteEntryInput(fieldName: "title", tone: .formal)
/// )
/// ```
public struct EntryActionsNamespace: Sendable {
    let client: FormeClient

    /// Generate a tone-aware rewrite of a field.
    public func rewrite(
        entryId: String,
        input: RewriteEntryInput
    ) async throws -> FormeResponse<RewriteEntryResult> {
        try await client.executor.post(
            "/management/entries/\(encodePathComponent(entryId))/actions/rewrite",
            body: input
        )
    }

    /// Record that the editor approved a previously-suggested action.
    public func approve(
        entryId: String,
        auditId: String
    ) async throws -> FormeResponse<EntryActionDecisionResult> {
        try await client.executor.postEmpty(
            "/management/entries/\(encodePathComponent(entryId))/actions/\(encodePathComponent(auditId))/approve"
        )
    }

    /// Record that the editor discarded a previously-suggested action.
    public func discard(
        entryId: String,
        auditId: String
    ) async throws -> FormeResponse<EntryActionDecisionResult> {
        try await client.executor.postEmpty(
            "/management/entries/\(encodePathComponent(entryId))/actions/\(encodePathComponent(auditId))/discard"
        )
    }
}
