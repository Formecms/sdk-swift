import Testing
import Foundation
@testable import Forme

@Suite("EntryNamespace — CRUD + PATCH via MockTransport")
struct EntryNamespaceTests {
    // MARK: - Helpers

    private func nowISO() -> String {
        "2026-04-14T10:30:00.000Z"
    }

    private func sampleEntryJSON(id: String = "entry-1", slug: String = "hello") -> String {
        """
        {
            "id": "\(id)",
            "accountId": "acc-1",
            "workspaceId": "ws-1",
            "environmentId": "env-1",
            "contentModelId": "cm-1",
            "status": "draft",
            "fields": {"slug": "\(slug)", "title": {"en-US": "Hello"}},
            "publishedFields": null,
            "publishedVersion": null,
            "firstPublishedAt": null,
            "publishedAt": null,
            "createdAt": "\(nowISO())",
            "updatedAt": "\(nowISO())"
        }
        """
    }

    // MARK: - List

    @Test func listSendsAuthHeaderAndParams() async throws {
        let transport = MockTransport()
        let envelope = """
        {
            "data": [\(sampleEntryJSON())],
            "pagination": {"total": 1, "limit": 25, "offset": 0}
        }
        """
        transport.enqueue(.raw(envelope))

        let client = makeTestClient(transport: transport)
        let result = try await client.entries.list(contentModelId: "cm-1", limit: 25)

        #expect(result.items.count == 1)
        #expect(result.total == 1)

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ce_secret_testkey")
        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("/management/entries"))
        #expect(urlString.contains("contentModelId=cm-1"))
        #expect(urlString.contains("limit=25"))
    }

    @Test func listSerializesFieldFilters() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .raw("""
            {"data": [], "pagination": {"total": 0, "limit": 25, "offset": 0}}
            """)
        )
        let client = makeTestClient(transport: transport)

        _ = try await client.entries.list(
            contentModelId: "cm-1",
            fields: ["slug": .value(.string("my-post"))]
        )

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("fields.slug=my-post"))
    }

    // MARK: - Get

    @Test func getReturnsDecodedEntry() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleEntryJSON(id: "abc", slug: "hello")))
        let client = makeTestClient(transport: transport)

        let entry = try await client.entries.get(id: "abc")

        #expect(entry.id == "abc")
        #expect(entry.fields["slug"]?.stringValue == "hello")
    }

    // MARK: - Create

    @Test func createSendsBody() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleEntryJSON(id: "new", slug: "new-slug")))
        let client = makeTestClient(transport: transport)

        let input = CreateEntryInput(
            contentModelId: "cm-1",
            fields: ["slug": .string("new-slug"), "title": .object(["en-US": .string("New")])]
        )
        let entry = try await client.entries.create(input)

        #expect(entry.id == "new")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode([String: FormeValue].self, from: body)
        #expect(decoded["contentModelId"]?.stringValue == "cm-1")
    }

    // MARK: - Patch

    @Test func patchSendsMergePatchContentTypeAndBody() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleEntryJSON(id: "abc", slug: "updated-slug")))
        let client = makeTestClient(transport: transport)

        let input = PatchEntryInput(fields: ["slug": .string("updated-slug")])
        let entry = try await client.entries.patch(id: "abc", input)

        #expect(entry.fields["slug"]?.stringValue == "updated-slug")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "PATCH")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type") == "application/merge-patch+json"
        )
    }

    @Test func patchForwardsIfMatchHeader() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleEntryJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.entries.patch(
            id: "abc",
            PatchEntryInput(fields: ["slug": .string("x")]),
            ifMatch: "W/\"abc-etag\""
        )

        let request = try #require(transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "If-Match") == "W/\"abc-etag\"")
    }

    @Test func patch412MapsToPreconditionFailedError() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 412,
                body: """
                {"error": {"code": "PRECONDITION_FAILED", "message": "stale"}}
                """.data(using: .utf8)!,
                headers: ["etag": "W/\"current\""]
            )
        )
        let client = makeTestClient(transport: transport)

        await #expect(throws: FormeError.self) {
            _ = try await client.entries.patch(
                id: "abc",
                PatchEntryInput(fields: ["slug": .string("x")]),
                ifMatch: "W/\"stale\""
            )
        }
    }

    @Test func patchLocaleQueryParamIsAppended() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleEntryJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.entries.patch(
            id: "abc",
            PatchEntryInput(fields: ["title": .object(["en-US": .string("Only EN")])]),
            locale: "*"
        )

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("locale=*") || url.contains("locale=%2A"))
    }

    // MARK: - Delete

    @Test func deleteSendsDelete() async throws {
        let transport = MockTransport()
        transport.enqueue(.init(statusCode: 204))
        let client = makeTestClient(transport: transport)

        try await client.entries.delete(id: "abc")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "DELETE")
    }

    // MARK: - Publish

    @Test func publishSendsPost() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleEntryJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.entries.publish(id: "abc")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        let url = request.url?.absoluteString ?? ""
        #expect(url.contains("/publish"))
    }

    // MARK: - Delivery API

    @Test func listDeliveryUsesDeliveryPath() async throws {
        let transport = MockTransport()
        let deliveryEnvelope = """
        {
            "items": [\(sampleEntryJSON())],
            "total": 1,
            "limit": 25,
            "offset": 0
        }
        """
        transport.enqueue(.raw(deliveryEnvelope))
        let client = makeTestClient(transport: transport)

        let result = try await client.entries.listDelivery()

        #expect(result.items.count == 1)
        #expect(result.total == 1)

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("/delivery/entries"))
    }

    // MARK: - Errors

    @Test func unauthorizedMapsToUnauthorized() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 401,
                body: """
                {"error": {"code": "UNAUTHORIZED", "message": "bad key"}}
                """.data(using: .utf8)!
            )
        )
        let client = makeTestClient(transport: transport)

        do {
            _ = try await client.entries.get(id: "abc")
            Issue.record("Expected error")
        } catch FormeError.unauthorized {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func validation400MapsToValidationError() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 400,
                body: """
                {
                    "error": {
                        "code": "VALIDATION_ERROR",
                        "message": "Invalid",
                        "details": [{"field": "slug", "message": "required"}]
                    }
                }
                """.data(using: .utf8)!
            )
        )
        let client = makeTestClient(transport: transport)

        do {
            let input = CreateEntryInput(contentModelId: "cm", fields: [:])
            _ = try await client.entries.create(input)
            Issue.record("Expected validation error")
        } catch FormeError.validation(let details) {
            #expect(details.count == 1)
            #expect(details.first?.field == "slug")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func rateLimitedMapsWithRetryAfter() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 429,
                body: """
                {"error": {"code": "RATE_LIMITED"}}
                """.data(using: .utf8)!,
                headers: ["Retry-After": "60"]
            )
        )
        let client = makeTestClient(transport: transport)

        do {
            _ = try await client.entries.get(id: "abc")
            Issue.record("Expected rate limited error")
        } catch FormeError.rateLimited(let retry) {
            #expect(retry == 60)
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }
}
