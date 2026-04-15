import Foundation
@testable import Forme

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Test-only mock transport that records sent requests and returns canned
/// responses. Safe under Swift 6 strict concurrency: uses a lock-protected
/// box for mutable state so the type stays `Sendable`.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct CannedResponse: Sendable {
        let statusCode: Int
        let body: Data
        let headers: [String: String]

        init(statusCode: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
        }

        static func json<T: Encodable>(_ value: T, statusCode: Int = 200) throws -> CannedResponse {
            let data = try JSONEncoder().encode(value)
            return CannedResponse(
                statusCode: statusCode,
                body: data,
                headers: ["Content-Type": "application/json"]
            )
        }

        static func raw(_ json: String, statusCode: Int = 200) -> CannedResponse {
            CannedResponse(
                statusCode: statusCode,
                body: json.data(using: .utf8) ?? Data(),
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    private let lock = NSLock()
    private var _responseQueue: [CannedResponse] = []
    private var _requests: [URLRequest] = []
    private var _defaultResponse = CannedResponse(statusCode: 500)

    /// Queue a response to be returned for the next request.
    func enqueue(_ response: CannedResponse) {
        lock.lock()
        defer { lock.unlock() }
        _responseQueue.append(response)
    }

    /// Set the response returned when the queue is empty.
    func setDefault(_ response: CannedResponse) {
        lock.lock()
        defer { lock.unlock() }
        _defaultResponse = response
    }

    /// Snapshot of recorded requests.
    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    /// The most recent request sent.
    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _requests.last
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Wrap the lock acquisition in a non-async helper so Swift 6 strict
        // concurrency doesn't reject the direct `NSLock.lock()` call from
        // an async context.
        let response = recordAndDequeue(request)

        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        return (response.body, http)
    }

    private func recordAndDequeue(_ request: URLRequest) -> CannedResponse {
        lock.lock()
        defer { lock.unlock() }
        _requests.append(request)
        return _responseQueue.isEmpty ? _defaultResponse : _responseQueue.removeFirst()
    }
}

/// Build a `FormeClient` wired to a `MockTransport` for tests.
func makeTestClient(
    transport: MockTransport,
    apiKey: String = "ce_secret_testkey",
    baseURL: URL = URL(string: "https://test.forme.sh")!
) -> FormeClient {
    let config = FormeConfiguration(apiKey: apiKey, baseURL: baseURL)
    return FormeClient(configuration: config, transport: transport)
}
