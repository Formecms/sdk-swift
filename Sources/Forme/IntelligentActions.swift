import Foundation

// MARK: - Tone presets

/// Tone preset for `entries.actions.rewrite()`.
public enum RewriteToneId: String, Sendable, Codable, CaseIterable {
    case formal
    case casual
    case friendly
    case technical
}

// MARK: - Rewrite input / output

/// Input for `entries.actions.rewrite(entryId:input:)`.
public struct RewriteEntryInput: Sendable, Encodable {
    public let fieldName: String
    public let tone: RewriteToneId
    public let locale: String?

    public init(fieldName: String, tone: RewriteToneId, locale: String? = nil) {
        self.fieldName = fieldName
        self.tone = tone
        self.locale = locale
    }
}

/// Result of a successful rewrite action.
public struct RewriteEntryResult: Sendable, Decodable {
    public let outputValue: String
    public let auditId: String
    public let model: String
    public let provider: String
    public let tokensIn: Int
    public let tokensOut: Int
    public let latencyMs: Int
    public let retried: Bool
    public let cacheReadTokens: Int?
    public let cacheCreationTokens: Int?
}

// MARK: - Approve / Discard result

/// Result of approving or discarding an AI action.
public struct EntryActionDecisionResult: Sendable, Decodable {
    public let ok: Bool
    public let auditId: String
    public let approvalStatus: String
    public let decidedAt: String
}

// MARK: - AI Usage

/// Monthly credit usage stats for the workspace.
public struct AiUsageStats: Sendable, Decodable {
    public let creditsUsed: Int
    public let creditsLimit: Int
    public let resetsAt: String
    public let breakdown: [String: Int]
}
