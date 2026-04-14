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
            if (error as NSError).code == NSURLErrorCancelled {
                throw FormeError.cancelled
            }
            throw FormeError.network(underlying: error)
        }
    }
}

// MARK: - Request execution

/// Internal request dispatcher used by every namespace. Handles auth
/// headers, body encoding, response decoding, and error mapping.
struct RequestExecutor: Sendable {
    let baseURL: URL
    let apiKey: String
    let transport: HTTPTransport
    let extraHeaders: [String: String]

    // MARK: - Typed calls

    func get<Response: Decodable & Sendable>(
        _ path: String
    ) async throws -> Response {
        try await executeWithoutBody(method: "GET", path: path)
    }

    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        try await executeWithBody(method: "POST", path: path, body: body)
    }

    func postEmpty<Response: Decodable & Sendable>(
        _ path: String
    ) async throws -> Response {
        try await executeWithoutBody(method: "POST", path: path)
    }

    func put<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        try await executeWithBody(method: "PUT", path: path, body: body)
    }

    func patch<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        ifMatch: String? = nil
    ) async throws -> Response {
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

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await executeWithoutBody(method: "DELETE", path: path)
    }

    // MARK: - Core

    private func executeWithBody<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        method: String,
        path: String,
        body: Body,
        extraHeaders: [String: String] = [:]
    ) async throws -> Response {
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
    ) async throws -> Response {
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
    ) async throws -> Response {
        let (data, response) = try await transport.send(request)
        return try decodeResponse(data: data, response: response)
    }

    private func decodeResponse<Response: Decodable & Sendable>(
        data: Data,
        response: HTTPURLResponse
    ) throws -> Response {
        if (200..<300).contains(response.statusCode) {
            // 204 No Content or empty body
            if data.isEmpty || response.statusCode == 204 {
                if let empty = EmptyResponse() as? Response {
                    return empty
                }
            }
            do {
                return try makeFormeDecoder().decode(Response.self, from: data)
            } catch {
                throw FormeError.decoding(underlying: error)
            }
        }

        // Non-success: map to typed errors
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
            let etag = response.value(forHTTPHeaderField: "etag")
                ?? response.value(forHTTPHeaderField: "ETag")
            throw FormeError.preconditionFailed(currentEtag: etag)
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw FormeError.rateLimited(retryAfter: retry)
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
        if !newPath.hasSuffix("/") && !pathPart.hasPrefix("/") {
            newPath += "/"
        } else if newPath.hasSuffix("/") && pathPart.hasPrefix("/") {
            newPath.removeLast()
        }
        newPath += pathPart
        components.path = newPath

        if let query = queryPart, !query.isEmpty {
            components.percentEncodedQuery = query
        }
        return components.url ?? self
    }
}
