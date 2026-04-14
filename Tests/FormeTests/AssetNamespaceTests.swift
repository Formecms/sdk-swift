import Testing
import Foundation
@testable import Forme

@Suite("AssetNamespace — CRUD + PATCH")
struct AssetNamespaceTests {
    private func sampleAssetJSON(id: String = "asset-1") -> String {
        """
        {
            "id": "\(id)",
            "accountId": "acc-1",
            "workspaceId": "ws-1",
            "environmentId": "env-1",
            "filename": "cover.jpg",
            "mimeType": "image/jpeg",
            "sizeBytes": 2048,
            "title": "Cover",
            "description": null,
            "alt": null,
            "url": null,
            "status": "draft",
            "publishedVersion": null,
            "firstPublishedAt": null,
            "publishedAt": null,
            "createdAt": "2026-04-14T10:00:00.000Z",
            "updatedAt": "2026-04-14T10:00:00.000Z"
        }
        """
    }

    @Test func listAssetsSendsGet() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .raw("""
            {
                "data": [\(sampleAssetJSON())],
                "pagination": {"total": 1, "limit": 25, "offset": 0}
            }
            """)
        )
        let client = makeTestClient(transport: transport)

        let result = try await client.assets.list()
        #expect(result.items.count == 1)
        #expect(result.items.first?.filename == "cover.jpg")

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("/management/assets"))
    }

    @Test func getAssetReturnsDecoded() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleAssetJSON(id: "a-1")))
        let client = makeTestClient(transport: transport)

        let asset = try await client.assets.get(id: "a-1")
        #expect(asset.id == "a-1")
        #expect(asset.title == "Cover")
    }

    @Test func patchAssetSendsMergePatchHeader() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleAssetJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.assets.patch(
            id: "a-1",
            UpdateAssetInput(title: "New title")
        )

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "PATCH")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type") == "application/merge-patch+json"
        )
    }

    @Test func patchAssetForwardsIfMatch() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleAssetJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.assets.patch(
            id: "a-1",
            UpdateAssetInput(title: "X"),
            ifMatch: "W/\"tag\""
        )

        let request = try #require(transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "If-Match") == "W/\"tag\"")
    }

    @Test func deliveryListUsesDeliveryPath() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .raw("""
            {"items": [\(sampleAssetJSON())], "total": 1, "limit": 25, "offset": 0}
            """)
        )
        let client = makeTestClient(transport: transport)

        let result = try await client.assets.listDelivery()
        #expect(result.items.count == 1)

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("/delivery/assets"))
    }
}
