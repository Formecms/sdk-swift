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
        let response = try await client.entries.list(contentModelId: "cm-1", limit: 25)

        #expect(response.value.items.count == 1)
        #expect(response.value.total == 1)

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

        let response = try await client.entries.get(id: "abc")

        #expect(response.value.id == "abc")
        #expect(response.value.fields["slug"]?.stringValue == "hello")
    }

    @Test func getExposesEtagOnSuccess() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 200,
                body: sampleEntryJSON().data(using: .utf8)!,
                headers: ["etag": "\"7\"", "Content-Type": "application/json"]
            )
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.get(id: "abc")

        // ETag (and full headers map, status) must be available so callers
        // can drive the GET → PATCH-with-If-Match concurrency flow.
        #expect(response.etag == "\"7\"")
        #expect(response.status == 200)
        #expect(response.headers["etag"] == "\"7\"")
        #expect(response.headers["content-type"] == "application/json")
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
        let response = try await client.entries.create(input)

        #expect(response.value.id == "new")

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
        let response = try await client.entries.patch(id: "abc", input)

        #expect(response.value.fields["slug"]?.stringValue == "updated-slug")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "PATCH")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type") == "application/merge-patch+json"
        )
    }

    @Test func patchExposesEtagOnSuccess() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 200,
                body: sampleEntryJSON().data(using: .utf8)!,
                headers: ["etag": "\"42\""]
            )
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.patch(
            id: "abc",
            PatchEntryInput(fields: ["slug": .string("x")])
        )
        #expect(response.etag == "\"42\"")
    }

    @Test func patchForwardsIfMatchHeader() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleEntryJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.entries.patch(
            id: "abc",
            PatchEntryInput(fields: ["slug": .string("x")]),
            ifMatch: "\"1\""
        )

        let request = try #require(transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"1\"")
    }

    @Test func patch412MapsToPreconditionFailedError() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 412,
                body: """
                {"error": {"code": "PRECONDITION_FAILED", "message": "stale"}}
                """.data(using: .utf8)!,
                headers: ["etag": "\"current\""]
            )
        )
        let client = makeTestClient(transport: transport)

        do {
            _ = try await client.entries.patch(
                id: "abc",
                PatchEntryInput(fields: ["slug": .string("x")]),
                ifMatch: "\"stale\""
            )
            Issue.record("Expected preconditionFailed error")
        } catch FormeError.preconditionFailed(let etag) {
            #expect(etag == "\"current\"")
        } catch {
            Issue.record("Wrong error: \(error)")
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

    // MARK: - Update (PUT) ETag

    @Test func updateForwardsIfMatchAndExposesEtag() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 200,
                body: sampleEntryJSON().data(using: .utf8)!,
                headers: ["etag": "\"3\""]
            )
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.update(
            id: "abc",
            UpdateEntryInput(fields: ["slug": .string("v2")]),
            ifMatch: "\"2\""
        )
        #expect(response.etag == "\"3\"")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"2\"")
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

    // MARK: - Versions

    @Test func versionsReturnsPaginatedListAndUsesCorrectPath() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .raw("""
            {
                "data": [
                    {
                        "id": "v-1",
                        "entryId": "abc",
                        "version": 1,
                        "fields": {"slug": "v1"},
                        "publishedAt": "\(nowISO())"
                    }
                ],
                "pagination": {"total": 1, "limit": 25, "offset": 0}
            }
            """)
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.versions(id: "abc", limit: 25)
        #expect(response.value.items.count == 1)
        #expect(response.value.items.first?.version == 1)
        #expect(response.value.items.first?.entryId == "abc")

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("/management/entries/abc/versions"))
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

        let response = try await client.entries.listDelivery()

        #expect(response.value.items.count == 1)
        #expect(response.value.total == 1)
        #expect(response.value.includes == nil) // no ?include=1

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("/delivery/entries"))
    }

    @Test func listDeliveryDecodesIncludesPayloadWhenIncludeRequested() async throws {
        let transport = MockTransport()
        let envelope = """
        {
            "items": [\(sampleEntryJSON(id: "post-1"))],
            "total": 1,
            "limit": 25,
            "offset": 0,
            "includes": {
                "entries": [\(sampleEntryJSON(id: "linked-entry"))],
                "assets": []
            }
        }
        """
        transport.enqueue(.raw(envelope))
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.listDelivery(include: 1)

        #expect(response.value.items.first?.id == "post-1")
        #expect(response.value.includes != nil)
        #expect(response.value.includes?.entries.first?.id == "linked-entry")
        #expect(response.value.includes?.assets.isEmpty == true)

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("include=1"))
    }

    @Test func getDeliveryDecodesEntryWithoutIncludes() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleEntryJSON(id: "abc")))
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.getDelivery(id: "abc")
        #expect(response.value.entry.id == "abc")
        #expect(response.value.includes == nil)
    }

    @Test func getDeliveryDecodesIncludesWhenPresent() async throws {
        let transport = MockTransport()
        let body = """
        {
            "id": "post-1",
            "contentModel": {"id": "cm-1", "apiId": "blogPost"},
            "fields": {"slug": "p1"},
            "createdAt": "\(nowISO())",
            "updatedAt": "\(nowISO())",
            "publishedAt": null,
            "publishedVersion": null,
            "firstPublishedAt": null,
            "includes": {
                "entries": [],
                "assets": []
            }
        }
        """
        transport.enqueue(.raw(body))
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.getDelivery(id: "post-1", include: 1)
        #expect(response.value.entry.id == "post-1")
        #expect(response.value.includes != nil)
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

    @Test func rateLimitedMapsWithNumericRetryAfter() async throws {
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

    @Test func rateLimitedHandlesHttpDateRetryAfter() async throws {
        // HTTP-date form per RFC 7231 §7.1.3. Use a date 30s in the future so
        // the parsed retry interval falls in a positive bracket regardless of
        // execution time slop.
        let future = Date().addingTimeInterval(30)
        let formatter = DateFormatter()
        formatter.locale = Foundation.Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let httpDate = formatter.string(from: future)

        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 429,
                body: "{}".data(using: .utf8)!,
                headers: ["Retry-After": httpDate]
            )
        )
        let client = makeTestClient(transport: transport)

        do {
            _ = try await client.entries.get(id: "abc")
            Issue.record("Expected rate limited error")
        } catch FormeError.rateLimited(let retry) {
            let parsed = try #require(retry)
            // Allow generous slack for clock + scheduling jitter.
            #expect(parsed > 0 && parsed <= 60)
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }
}
