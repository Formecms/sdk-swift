import Testing
import Foundation
@testable import Forme

@Suite("Transport — request construction + response decoding")
struct TransportTests {
    private let workspaceJSON = """
    {
        "id": "ws-1",
        "accountId": "acc-1",
        "accountName": "Acme",
        "name": "Marketing",
        "slug": "marketing",
        "createdAt": "2026-04-14T10:00:00.000Z",
        "updatedAt": "2026-04-14T10:00:00.000Z"
    }
    """

    @Test func configuredTimeoutAppliesToRequest() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(workspaceJSON))

        let config = FormeConfiguration(
            apiKey: "ce_secret_x",
            baseURL: URL(string: "https://test.forme.sh")!,
            timeoutSeconds: 7
        )
        let client = FormeClient(configuration: config, transport: transport)
        _ = try await client.workspace.get()

        let request = try #require(transport.lastRequest)
        // The default URLSession request timeout is 60s. Confirm our 7s
        // override propagated through to URLRequest.timeoutInterval — this
        // is the knob iOS apps need to bound network latency.
        #expect(request.timeoutInterval == 7)
    }

    @Test func defaultTimeoutIs30Seconds() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(workspaceJSON))
        // No timeoutSeconds override.
        let config = FormeConfiguration(
            apiKey: "k",
            baseURL: URL(string: "https://test.forme.sh")!
        )
        let client = FormeClient(configuration: config, transport: transport)
        _ = try await client.workspace.get()

        let request = try #require(transport.lastRequest)
        #expect(request.timeoutInterval == 30)
    }

    @Test func extraHeadersAreSent() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(workspaceJSON))
        let config = FormeConfiguration(
            apiKey: "k",
            baseURL: URL(string: "https://test.forme.sh")!,
            extraHeaders: ["X-Forme-Trace-Id": "abc-123"]
        )
        let client = FormeClient(configuration: config, transport: transport)
        _ = try await client.workspace.get()

        let request = try #require(transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "X-Forme-Trace-Id") == "abc-123")
    }

    @Test func acceptHeaderIsApplicationJson() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(workspaceJSON))
        let client = makeTestClient(transport: transport)
        _ = try await client.workspace.get()

        let request = try #require(transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func headersMapIsLowercased() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 200,
                body: """
                {"id": "ws-1", "accountId": "a", "accountName": "n", "name": "n", "slug": "s",
                 "createdAt": "2026-04-14T10:00:00.000Z", "updatedAt": "2026-04-14T10:00:00.000Z"}
                """.data(using: .utf8)!,
                headers: ["X-Forme-Custom": "value", "ETag": "\"1\""]
            )
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.workspace.get()
        // All headers exposed lowercased — matches TS SDK's `headers` map for
        // case-insensitive cross-SDK consistency.
        #expect(response.headers["etag"] == "\"1\"")
        #expect(response.headers["x-forme-custom"] == "value")
    }
}
