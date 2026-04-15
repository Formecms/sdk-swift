import Testing
import Foundation
@testable import Forme

@Suite("AssetNamespace — CRUD + PATCH + multipart upload")
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

        let response = try await client.assets.list()
        #expect(response.value.items.count == 1)
        #expect(response.value.items.first?.filename == "cover.jpg")

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("/management/assets"))
    }

    @Test func getAssetReturnsDecoded() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleAssetJSON(id: "a-1")))
        let client = makeTestClient(transport: transport)

        let response = try await client.assets.get(id: "a-1")
        #expect(response.value.id == "a-1")
        #expect(response.value.title == "Cover")
    }

    @Test func getAssetExposesEtag() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 200,
                body: sampleAssetJSON().data(using: .utf8)!,
                headers: ["etag": "\"5\""]
            )
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.assets.get(id: "a-1")
        #expect(response.etag == "\"5\"")
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
            ifMatch: "\"7\""
        )

        let request = try #require(transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"7\"")
    }

    @Test func updateAssetForwardsIfMatch() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleAssetJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.assets.update(
            id: "a-1",
            UpdateAssetInput(title: "X"),
            ifMatch: "\"3\""
        )

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"3\"")
    }

    @Test func deliveryListUsesDeliveryPath() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .raw("""
            {"items": [\(sampleAssetJSON())], "total": 1, "limit": 25, "offset": 0}
            """)
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.assets.listDelivery()
        #expect(response.value.items.count == 1)

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.contains("/delivery/assets"))
    }

    // MARK: - Upload

    @Test func uploadConstructsMultipartBodyWithFileAndMetadata() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleAssetJSON(id: "uploaded")))
        let client = makeTestClient(transport: transport)

        let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00]) // JPEG magic-ish bytes
        let response = try await client.assets.upload(
            data: imageBytes,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            title: "Sunset",
            alt: "Sunset over the ocean"
        )
        #expect(response.value.id == "uploaded")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        let url = request.url?.absoluteString ?? ""
        #expect(url.hasSuffix("/management/assets"))

        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))

        let body = try #require(request.httpBody)
        let bodyString = String(decoding: body, as: UTF8.self)

        // Field part: file
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\""))
        #expect(bodyString.contains("Content-Type: image/jpeg"))

        // Text fields
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"title\""))
        #expect(bodyString.contains("Sunset"))
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"alt\""))
        #expect(bodyString.contains("Sunset over the ocean"))

        // Body must end with the closing boundary.
        let boundary = contentType.replacingOccurrences(
            of: "multipart/form-data; boundary=",
            with: ""
        )
        #expect(bodyString.contains("--\(boundary)--\r\n"))
    }

    @Test func uploadWithoutOptionalFieldsOnlySendsFile() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleAssetJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.assets.upload(
            data: Data("hello".utf8),
            filename: "x.txt",
            mimeType: "text/plain"
        )

        let body = try #require(transport.lastRequest?.httpBody)
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("name=\"file\""))
        #expect(!bodyString.contains("name=\"title\""))
        #expect(!bodyString.contains("name=\"alt\""))
    }

    // MARK: - Replace file

    @Test func replaceFileTargetsCorrectPathAndSendsMultipart() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(sampleAssetJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.assets.replaceFile(
            id: "a-1",
            data: Data([0x00, 0x01]),
            filename: "v2.png",
            mimeType: "image/png",
            ifMatch: "\"4\""
        )

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        let url = request.url?.absoluteString ?? ""
        #expect(url.hasSuffix("/management/assets/a-1/file"))
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"4\"")

        let body = try #require(request.httpBody)
        let bodyString = String(decoding: body, as: UTF8.self)
        #expect(bodyString.contains("filename=\"v2.png\""))
        #expect(bodyString.contains("Content-Type: image/png"))
    }

    // MARK: - Download

    @Test func downloadFileReturnsRawBytesAndPreservesHeaders() async throws {
        let transport = MockTransport()
        let bytes = Data([0xCA, 0xFE, 0xBA, 0xBE])
        transport.enqueue(
            .init(
                statusCode: 200,
                body: bytes,
                headers: [
                    "Content-Type": "image/png",
                    "Content-Length": "4",
                ]
            )
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.assets.downloadFile(id: "a-1")
        #expect(response.value == bytes)
        #expect(response.status == 200)
        #expect(response.headers["content-type"] == "image/png")

        let url = try #require(transport.lastRequest?.url?.absoluteString)
        #expect(url.hasSuffix("/management/assets/a-1/file"))
    }

    @Test func downloadFile404MapsToNotFound() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .init(
                statusCode: 404,
                body: """
                {"error": {"code": "NOT_FOUND", "message": "asset"}}
                """.data(using: .utf8)!
            )
        )
        let client = makeTestClient(transport: transport)

        await #expect(throws: FormeError.self) {
            _ = try await client.assets.downloadFile(id: "missing")
        }
    }

    // MARK: - Versions

    @Test func versionsReturnsPaginatedAssetVersions() async throws {
        let transport = MockTransport()
        transport.enqueue(
            .raw("""
            {
                "data": [
                    {
                        "id": "v-1",
                        "assetId": "a-1",
                        "version": 1,
                        "filename": "cover-v1.jpg",
                        "mimeType": "image/jpeg",
                        "sizeBytes": 2048,
                        "title": "v1",
                        "description": null,
                        "alt": null,
                        "publishedAt": "2026-04-14T10:00:00.000Z"
                    }
                ],
                "pagination": {"total": 1, "limit": 25, "offset": 0}
            }
            """)
        )
        let client = makeTestClient(transport: transport)

        let response = try await client.assets.versions(id: "a-1")
        #expect(response.value.items.count == 1)
        #expect(response.value.items.first?.assetId == "a-1")
        #expect(response.value.items.first?.version == 1)
    }

    // MARK: - fileUrl

    @Test func fileUrlBuildsDeliveryURLWithoutNetwork() {
        let transport = MockTransport()
        let client = makeTestClient(
            transport: transport,
            baseURL: URL(string: "https://delivery.forme.sh")!
        )
        let url = client.assets.fileUrl(id: "a-1")
        #expect(url.absoluteString == "https://delivery.forme.sh/delivery/assets/a-1/file")
        #expect(transport.lastRequest == nil) // no network
    }
}
