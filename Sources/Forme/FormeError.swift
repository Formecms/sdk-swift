import Foundation

/// Errors thrown by the Forme SDK.
///
/// Use `switch` exhaustively in your `catch` to handle each case. All cases
/// carry enough context to render a meaningful message without needing to
/// inspect the underlying HTTP response.
public enum FormeError: Error, Sendable {
    /// Network-level failure — DNS, connection refused, TLS, offline, etc.
    case network(underlying: Error)

    /// The response body could not be decoded into the expected type.
    case decoding(underlying: Error)

    /// The server returned a non-2xx HTTP response. `apiError` carries the
    /// structured error body when present (Forme's `{error: {code, message}}`
    /// envelope).
    case http(status: Int, apiError: APIError?)

    /// The API key is invalid or expired (401).
    case unauthorized

    /// The resource doesn't exist or the caller lacks permission (404).
    case notFound(resource: String, id: String?)

    /// The request was rate-limited (429). `retryAfter` is the suggested
    /// delay in seconds if the server provided `Retry-After`.
    case rateLimited(retryAfter: TimeInterval?)

    /// The configured API key is missing or malformed (before the request
    /// even reaches the network).
    case invalidAPIKey(hint: String)

    /// The caller cancelled the task.
    case cancelled

    /// A write request with `If-Match` was rejected because the stored ETag
    /// no longer matches (412 Precondition Failed). The caller should re-read
    /// the resource and retry.
    case preconditionFailed(currentEtag: String?)

    /// The request failed validation server-side (400).
    case validation(details: [APIErrorDetail])
}

/// Structured error envelope returned by the Forme API.
public struct APIError: Sendable, Codable, Equatable {
    public let code: String
    public let message: String?
    public let details: [APIErrorDetail]?

    public init(code: String, message: String? = nil, details: [APIErrorDetail]? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

/// A single validation issue within an `APIError`.
public struct APIErrorDetail: Sendable, Codable, Equatable {
    public let field: String
    public let message: String
    public let validOperators: [String]?
    public let validFields: [String]?

    public init(
        field: String,
        message: String,
        validOperators: [String]? = nil,
        validFields: [String]? = nil
    ) {
        self.field = field
        self.message = message
        self.validOperators = validOperators
        self.validFields = validFields
    }
}

// MARK: - LocalizedError

extension FormeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .decoding(let underlying):
            return "Failed to decode response: \(underlying.localizedDescription)"
        case .http(let status, let apiError):
            if let msg = apiError?.message {
                return "HTTP \(status): \(msg)"
            }
            return "HTTP \(status)"
        case .unauthorized:
            return "Unauthorized — check that your API key is valid and not revoked."
        case .notFound(let resource, let id):
            if let id = id {
                return "\(resource) not found (id: \(id))"
            }
            return "\(resource) not found"
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Rate limited — retry after \(Int(retry))s"
            }
            return "Rate limited"
        case .invalidAPIKey(let hint):
            return "Invalid API key: \(hint)"
        case .cancelled:
            return "Request was cancelled"
        case .preconditionFailed:
            return "Stale entry — If-Match did not match current version. Re-fetch and retry."
        case .validation(let details):
            let msgs = details.map { "\($0.field): \($0.message)" }.joined(separator: "; ")
            return "Validation failed: \(msgs)"
        }
    }
}
