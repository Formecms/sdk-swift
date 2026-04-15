import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP transport protocol.
///
/// The default implementation uses `URLSession`. The protocol is public so
/// tests (and advanced users) can inject a mock transport without running
/// real network I/O. Future transports (e.g., `AsyncHTTPClient` for
/// server-side Swift on Linux) can slot in without changing the public API.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production transport backed by `URLSession`.
struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FormeError.network(
                    underlying: NSError(
                        domain: "Forme",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"]
                    )
                )
            }
            return (data, http)
        } catch let error as FormeError {
            throw error
        } catch {
            throw mapURLSessionError(error)
        }
    }
}

/// Map an error thrown by `URLSession.data(for:)` (or any equivalent
/// transport) to a typed `FormeError`. Cancellation — whether caused by
/// `Task.cancel()` or an explicit URLSessionTask cancellation — surfaces
/// as `FormeError.cancelled` so SwiftUI-driven callers can branch on it.
func mapURLSessionError(_ error: Error) -> FormeError {
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
        return .cancelled
    }
    if ns.code == NSURLErrorCancelled {
        return .cancelled
    }
    return .network(underlying: error)
}

// MARK: - Request execution

/// Internal request dispatcher used by every namespace. Handles auth
/// headers, body encoding, response decoding, and error mapping.
struct RequestExecutor: Sendable {
    let baseURL: URL
    let apiKey: String
    let transport: HTTPTransport
    let extraHeaders: [String: String]
    let timeoutSeconds: TimeInterval

    // MARK: - Typed calls

    func get<Response: Decodable & Sendable>(
        _ path: String
    ) async throws -> FormeResponse<Response> {
        try await executeWithoutBody(method: "GET", path: path)
    }

    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body
    ) async throws -> FormeResponse<Response> {
        try await executeWithBody(method: "POST", path: path, body: body)
    }

    func postEmpty<Response: Decodable & Sendable>(
        _ path: String
    ) async throws -> FormeResponse<Response> {
        try await executeWithoutBody(method: "POST", path: path)
    }

    func put<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        ifMatch: String? = nil
    ) async throws -> FormeResponse<Response> {
        var headers: [String: String] = [:]
        if let ifMatch = ifMatch {
            headers["If-Match"] = ifMatch
        }
        return try await executeWithBody(
            method: "PUT",
            path: path,
            body: body,
            extraHeaders: headers
        )
    }

    func patch<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        ifMatch: String? = nil
    ) async throws -> FormeResponse<Response> {
        var headers: [String: String] = ["Content-Type": "application/merge-patch+json"]
        if let ifMatch = ifMatch {
            headers["If-Match"] = ifMatch
        }
        return try await executeWithBody(
            method: "PATCH",
            path: path,
            body: body,
            extraHeaders: headers
        )
    }

    /// Send a request with a pre-built raw body (e.g. multipart). The caller
    /// supplies the `Content-Type` header.
    func sendRaw<Response: Decodable & Sendable>(
        method: String,
        path: String,
        body: Data,
        contentType: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> FormeResponse<Response> {
        var headers = extraHeaders
        headers["Content-Type"] = contentType
        var request = try makeRequest(method: method, path: path, extraHeaders: headers)
        request.httpBody = body
        return try await executeRequest(request)
    }

    /// Download a binary payload (e.g. asset file). Returns the raw bytes
    /// plus response metadata. Bypasses JSON decode.
    func download(_ path: String) async throws -> FormeResponse<Data> {
        let request = try makeRequest(method: "GET", path: path, extraHeaders: [:])
        let (data, response) = try await transport.send(request)
        if (200..<300).contains(response.statusCode) {
            return FormeResponse(
                value: data,
                etag: extractEtag(response),
                status: response.statusCode,
                headers: extractHeaders(response)
            )
        }
        try throwHTTPError(data: data, response: response)
    }

    func delete(_ path: String) async throws {
        let _: FormeResponse<EmptyResponse> = try await executeWithoutBody(method: "DELETE", path: path)
    }

    // MARK: - Core

    private func executeWithBody<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        method: String,
        path: String,
        body: Body,
        extraHeaders: [String: String] = [:]
    ) async throws -> FormeResponse<Response> {
        var request = try makeRequest(method: method, path: path, extraHeaders: extraHeaders)
        // Only set Content-Type if caller didn't already (PATCH sets merge-patch+json)
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = try makeFormeEncoder().encode(body)
        return try await executeRequest(request)
    }

    private func executeWithoutBody<Response: Decodable & Sendable>(
        method: String,
        path: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> FormeResponse<Response> {
        let request = try makeRequest(method: method, path: path, extraHeaders: extraHeaders)
        return try await executeRequest(request)
    }

    private func makeRequest(
        method: String,
        path: String,
        extraHeaders: [String: String]
    ) throws -> URLRequest {
        let url = baseURL.appendingRelative(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in self.extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        for (k, v) in extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        return request
    }

    private func executeRequest<Response: Decodable & Sendable>(
        _ request: URLRequest
    ) async throws -> FormeResponse<Response> {
        let (data, response) = try await transport.send(request)
        return try decodeResponse(data: data, response: response)
    }

    private func decodeResponse<Response: Decodable & Sendable>(
        data: Data,
        response: HTTPURLResponse
    ) throws -> FormeResponse<Response> {
        if (200..<300).contains(response.statusCode) {
            // 204 No Content or empty body
            if data.isEmpty || response.statusCode == 204 {
                if let empty = EmptyResponse() as? Response {
                    return FormeResponse(
                        value: empty,
                        etag: extractEtag(response),
                        status: response.statusCode,
                        headers: extractHeaders(response)
                    )
                }
            }
            do {
                let value = try makeFormeDecoder().decode(Response.self, from: data)
                return FormeResponse(
                    value: value,
                    etag: extractEtag(response),
                    status: response.statusCode,
                    headers: extractHeaders(response)
                )
            } catch {
                throw FormeError.decoding(underlying: error)
            }
        }

        try throwHTTPError(data: data, response: response)
    }

    /// Map a non-2xx response to a typed `FormeError` and throw.
    private func throwHTTPError(data: Data, response: HTTPURLResponse) throws -> Never {
        let apiError = (try? makeFormeDecoder().decode(APIErrorEnvelope.self, from: data))?.error

        switch response.statusCode {
        case 401:
            throw FormeError.unauthorized
        case 404:
            throw FormeError.notFound(
                resource: apiError?.code ?? "Resource",
                id: nil
            )
        case 412:
            throw FormeError.preconditionFailed(currentEtag: extractEtag(response))
        case 429:
            throw FormeError.rateLimited(retryAfter: parseRetryAfter(response))
        case 400:
            if let err = apiError, let details = err.details {
                throw FormeError.validation(details: details)
            }
            throw FormeError.http(status: response.statusCode, apiError: apiError)
        default:
            throw FormeError.http(status: response.statusCode, apiError: apiError)
        }
    }
}

// MARK: - Header helpers

/// Read the strong `ETag` header in a case-insensitive way.
func extractEtag(_ response: HTTPURLResponse) -> String? {
    response.value(forHTTPHeaderField: "etag")
        ?? response.value(forHTTPHeaderField: "ETag")
}

/// Build a lowercased-keys snapshot of the response headers.
func extractHeaders(_ response: HTTPURLResponse) -> [String: String] {
    var out: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
        guard let k = key as? String, let v = value as? String else { continue }
        out[k.lowercased()] = v
    }
    return out
}

/// Parse an HTTP `Retry-After` header. RFC 7231 §7.1.3 allows two forms:
/// numeric seconds (e.g. `Retry-After: 120`) OR an HTTP-date
/// (e.g. `Retry-After: Wed, 21 Oct 2025 07:28:00 GMT`).
/// Returns the delay in seconds, or `nil` if the header is missing/malformed.
func parseRetryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
    guard let raw = response.value(forHTTPHeaderField: "Retry-After") else {
        return nil
    }
    if let seconds = TimeInterval(raw) {
        return max(0, seconds)
    }
    if let date = httpDateFormatter.date(from: raw) {
        return max(0, date.timeIntervalSinceNow)
    }
    return nil
}

private let httpDateFormatter: DateFormatter = {
    // RFC 7231 §7.1.1.1 prefers IMF-fixdate; we accept it here. Other
    // historical forms (RFC 850, asctime) are uncommon in modern servers.
    let f = DateFormatter()
    f.locale = Foundation.Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "GMT")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return f
}()

// MARK: - Helpers

struct EmptyResponse: Codable, Sendable {
    init() {}
}

struct APIErrorEnvelope: Decodable, Sendable {
    let error: APIError
}

extension URL {
    /// Append a relative path (which may include a leading slash and query
    /// string) to a URL without tripping over `URL`'s reluctance to append
    /// path components that contain `?`.
    ///
    /// Path components are NOT percent-encoded — callers are responsible
    /// for encoding any user-supplied path segments via
    /// `Transport.encodePathComponent(_:)`. The query portion is stored as
    /// `percentEncodedQuery` verbatim because `URLBuilder.buildQuery` already
    /// emits a fully-encoded string.
    func appendingRelative(_ path: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }

        // Split path from query string
        let pathPart: String
        let queryPart: String?
        if let q = path.firstIndex(of: "?") {
            pathPart = String(path[..<q])
            queryPart = String(path[path.index(after: q)...])
        } else {
            pathPart = path
            queryPart = nil
        }

        // Append path
        var newPath = components.path
        if pathPart.isEmpty {
            // No path to append — fall through to query handling.
        } else if newPath.isEmpty {
            newPath = pathPart.hasPrefix("/") ? pathPart : "/" + pathPart
        } else if newPath.hasSuffix("/") && pathPart.hasPrefix("/") {
            newPath += String(pathPart.dropFirst())
        } else if !newPath.hasSuffix("/") && !pathPart.hasPrefix("/") {
            newPath += "/" + pathPart
        } else {
            newPath += pathPart
        }
        components.path = newPath

        if let query = queryPart, !query.isEmpty {
            components.percentEncodedQuery = query
        }
        return components.url ?? self
    }
}

/// Percent-encode a single URL path component so that special characters
/// (`/`, `?`, `#`, `%`, etc.) cannot break routing or smuggle a query
/// string. Use this at every namespace call site that interpolates a
/// user-supplied or runtime-derived id into a path.
///
/// Forme IDs are UUIDs in practice, which need no encoding — this is a
/// defensive helper that future-proofs against slug-style ids.
func encodePathComponent(_ raw: String) -> String {
    raw.addingPercentEncoding(withAllowedCharacters: .urlPathComponentAllowed) ?? raw
}

private extension CharacterSet {
    /// Path-component-allowed chars per RFC 3986 §3.3 (`pchar` minus `/`).
    /// `URLPathAllowedCharacters` lets `/` through, which is wrong for a
    /// single component.
    static let urlPathComponentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()
}
