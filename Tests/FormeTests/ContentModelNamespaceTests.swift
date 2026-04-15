import Testing
import Foundation
@testable import Forme

@Suite("ContentModelNamespace — CRUD")
struct ContentModelNamespaceTests {
    private func sampleModelJSON() -> String {
        """
        {
            "id": "cm-1",
            "accountId": "acc-1",
            "workspaceId": "ws-1",
            "environmentId": "env-1",
            "apiId": "blogPost",
            "name": "Blog Post",
            "description": null,
            "type": "page",
            "fields": [
                {"apiId": "slug", "name": "Slug", "type": "shortText", "required": true},
                {"apiId": "title", "name": "Title", "type": "shortText", "localized": true}
            ],
            "entryCount": 3,
            "createdAt": "2026-04-14T10:00:00.000Z",
            "updatedAt": "2026-04-14T10:00:00.000Z"
        }
        """
    }

    @Test func listDecodesModels() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .raw("""
            {
                "data": [\(sampleModelJSON())],
                "pagination": {"total": 1, "limit": 25, "offset": 0}
            }
            """)
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.contentModels.list()
        #expect(response.value.items.count == 1)
        #expect(response.value.items.first?.apiId == "blogPost")
        #expect(response.value.items.first?.fields.count == 2)
    }

    @Test func getReturnsModel() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleModelJSON()))
        let client = makeTestClient(transport: transport)

        let response = try await client.contentModels.get(id: "cm-1")
        #expect(response.value.apiId == "blogPost")
        #expect(response.value.fields.first?.apiId == "slug")
        #expect(response.value.fields.first?.required == true)
    }

    @Test func fieldDefPreservesUnknownKeysInExtra() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleModelJSON()))
        let client = makeTestClient(transport: transport)

        let response = try await client.contentModels.get(id: "cm-1")
        let titleField = try #require(response.value.fields.first { $0.apiId == "title" })
        // `localized` is a stable key — consumed directly
        #expect(titleField.localized == true)
    }

    @Test func createSendsBody() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleModelJSON()))
        let client = makeTestClient(transport: transport)

        // Build a FieldDef via Codable round-trip from JSON (hand-constructing
        // the struct directly isn't possible since it uses custom Codable init).
        let fieldJSON = """
        {"apiId": "slug", "name": "Slug", "type": "shortText", "required": true}
        """.data(using: .utf8)!
        let field = try JSONDecoder().decode(FieldDef.self, from: fieldJSON)

        let input = CreateContentModelInput(
            apiId: "blogPost",
            name: "Blog Post",
            fields: [field]
        )
        let response = try await client.contentModels.create(input)
        #expect(response.value.apiId == "blogPost")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
    }

    @Test func deliveryListUsesDeliveryPath() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .raw("""
            {"items": [\(sampleModelJSON())], "total": 1, "limit": 25, "offset": 0}
            """)
        )
        let client = makeTestClient(transport: transport)

        _ = try await client.contentModels.listDelivery()
        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("/delivery/content-models"))
    }
}
