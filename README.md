# Forme Swift SDK

Official Swift SDK for [Forme](https://forme.build), the AI-native headless CMS.

**Native async/await, strict Sendable, zero third-party dependencies.**

- ✨ Swift 5.9+ / iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+
- 🚀 Modern async/await throughout — no callbacks, no Combine
- 🛡️ `Sendable`-correct under Swift 6 strict concurrency
- 📦 `URLSession` only — no Alamofire, no third-party networking deps
- ✍️ Type-safe PATCH with optimistic concurrency (ETag / If-Match)

## Installation

Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Formecms/sdk-swift", from: "0.1.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Forme", package: "sdk-swift")
    ])
]
```

Or in Xcode: **File → Add Package Dependencies…** and paste
`https://github.com/Formecms/sdk-swift`.

## Quick start

```swift
import Forme

let client = FormeClient(
    apiKey: "ce_read_...",
    baseURL: URL(string: "https://delivery.forme.sh")!,
    defaultLocale: "en-US"
)

let response = try await client.entries.listDelivery(contentModelId: "blogPost", limit: 10)
for entry in response.value.items {
    let title = entry.fields["title"]?.stringValue ?? "Untitled"
    print(title)
}
```

> **Security:** never ship a Secret Key (`ce_secret_...`) in a published iOS
> binary. Use a Read Key (`ce_read_...`) for read-only Delivery access, or
> proxy Management API calls through your own backend.

## Response envelope

Every SDK call returns `FormeResponse<T>`:

```swift
public struct FormeResponse<Value: Sendable>: Sendable {
    public let value: Value           // the decoded payload
    public let etag: String?          // strong ETag (for optimistic concurrency)
    public let status: Int            // HTTP status code
    public let headers: [String: String]  // lowercased-key headers map
}
```

This shape mirrors the TypeScript SDK's `ApiResponse<T>` so callers moving
between SDKs find the same mental model. `value` carries the decoded payload,
`etag` enables the GET → PATCH-with-If-Match concurrency flow, and `headers`
exposes everything else (e.g., `x-ratelimit-remaining`).

## Endpoint coverage

### Delivery API (Read Key — `ce_read_...`)

| Namespace        | Methods                                                                                       |
| ---------------- | --------------------------------------------------------------------------------------------- |
| `entries`        | `listDelivery(...)`, `getDelivery(id:locale:include:)`                                        |
| `contentModels`  | `listDelivery(...)`, `getDelivery(id:)`                                                       |
| `assets`         | `listDelivery(...)`, `getDelivery(id:locale:)`, `fileUrl(id:)` (URL builder, no network call) |
| `locales`        | `listDelivery()`                                                                              |

### Management API (Secret Key — `ce_secret_...`)

| Namespace        | Methods                                                                                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `entries`        | `list(...)`, `get(id:locale:)`, `create(...)`, `update(id:_:ifMatch:)`, `patch(id:_:locale:ifMatch:)`, `delete(id:)`, `publish(id:)`, `unpublish(id:)`, `versions(id:)` |
| `contentModels`  | `list(...)`, `get(id:)`, `create(...)`, `update(id:_:)`, `delete(id:)`                                                                                             |
| `assets`         | `list(...)`, `get(id:locale:)`, `upload(data:filename:mimeType:title:description:alt:)`, `replaceFile(id:data:filename:mimeType:ifMatch:)`, `downloadFile(id:)`, `update(id:_:ifMatch:)`, `patch(id:_:ifMatch:)`, `delete(id:)`, `publish(id:)`, `unpublish(id:)`, `versions(id:)` |
| `environments`   | `list()`, `get(id:)`, `create(...)`, `update(id:_:)`, `delete(id:)`                                                                                                |
| `locales`        | `list()`, `get(id:)`, `create(...)`, `update(id:_:)`, `delete(id:)`                                                                                                |
| `workspace`      | `get()`, `update(name:)`                                                                                                                                           |
| `apiKeys`        | `list()`, `create(...)`, `revoke(id:)`                                                                                                                             |

## Management API (Secret Key required)

```swift
let mgmt = FormeClient(
    apiKey: "ce_secret_...",
    baseURL: URL(string: "https://management.forme.sh")!
)

// Create
let created = try await mgmt.entries.create(
    CreateEntryInput(
        contentModelId: "cm-123",
        fields: [
            "slug": .string("hello-world"),
            "title": .object(["en-US": .string("Hello")])
        ]
    )
)

// Patch (shallow merge — omitted keys preserved, null clears)
let patched = try await mgmt.entries.patch(
    id: created.value.id,
    PatchEntryInput(fields: ["title": .object(["en-US": .string("Hello, world")])])
)

// Publish
_ = try await mgmt.entries.publish(id: created.value.id)
```

## Asset upload (multipart)

The `upload` method handles `multipart/form-data` body construction internally
per RFC 7578. Pass raw `Data` (e.g. from `UIImage.jpegData(...)` or a file
read), the filename, and the MIME type.

```swift
import UIKit

let imageData = uiImage.jpegData(compressionQuality: 0.9)!

let response = try await mgmt.assets.upload(
    data: imageData,
    filename: "photo.jpg",
    mimeType: "image/jpeg",
    title: "Sunset",
    alt: "Sunset over the ocean"
)
let asset = response.value
print(asset.id, asset.url ?? "")

// Construct the public URL for rendering (no network call):
let displayURL = client.assets.fileUrl(id: asset.id)

// Replace the underlying file later:
let v2Data = newImage.jpegData(compressionQuality: 0.9)!
_ = try await mgmt.assets.replaceFile(
    id: asset.id,
    data: v2Data,
    filename: "photo-v2.jpg",
    mimeType: "image/jpeg",
    ifMatch: response.etag      // optional — protect against concurrent edits
)

// Download the bytes directly (Management API):
let downloaded = try await mgmt.assets.downloadFile(id: asset.id)
let bytes = downloaded.value          // Data
let mime = downloaded.headers["content-type"] ?? "application/octet-stream"
```

## Optimistic concurrency (ETag / If-Match)

The Forme API returns a strong ETag header (e.g. `"5"`) on every GET, PUT, and
PATCH. Round-trip the ETag through `ifMatch` to detect stale writes:

```swift
// 1. Fresh GET — read the ETag from the response.
let read = try await mgmt.entries.get(id: "abc")
let etag = read.etag                   // e.g. "\"5\""

// 2. Conditional PATCH — server returns 412 if anyone else wrote in between.
do {
    let updated = try await mgmt.entries.patch(
        id: "abc",
        PatchEntryInput(fields: ["slug": .string("v2")]),
        ifMatch: etag
    )
    let nextEtag = updated.etag        // refresh for the next write
} catch FormeError.preconditionFailed(let serverEtag) {
    // Stale — re-fetch and retry. `serverEtag` is the current value on the
    // server so you can avoid a second GET.
}
```

This works on **GET, PUT, and PATCH** for both entries and assets. The ETag
is also exposed on the upload response so the very first write after upload
can already participate.

## Including linked entries / assets (Delivery API)

Pass `include: 1` to ask the Delivery API to inline linked entries and assets.
Without it the SDK still works, but reference fields only carry ids:

```swift
let response = try await client.entries.listDelivery(
    contentModelId: "blogPost",
    include: 1,
    limit: 10
)
for post in response.value.items {
    print(post.id)
}
// Linked author entries + cover assets, fully decoded:
let authors = response.value.includes?.entries ?? []
let covers  = response.value.includes?.assets ?? []
```

The single-entry endpoint returns `DeliveryEntryResponse { entry, includes? }`:

```swift
let one = try await client.entries.getDelivery(id: "abc", include: 1)
let post = one.value.entry
let linked = one.value.includes
```

## Field filtering

The Delivery API supports rich filtering via the `fields` parameter:

```swift
// Equality (the 80% case)
let post = try await client.entries.listDelivery(
    contentModelId: "blogPost",
    fields: ["slug": .value(.string("my-post"))],
    limit: 1
).value.items.first

// Operator
let popular = try await client.entries.listDelivery(
    contentModelId: "blogPost",
    fields: ["viewCount": .operators(["gte": .int(1000)])]
)

// List (in)
let tagged = try await client.entries.listDelivery(
    contentModelId: "blogPost",
    fields: ["tags": .operators(["in": .array(["ai", "ml"])])]
)
```

Supported operators: `eq`, `ne`, `in`, `nin`, `gt`, `gte`, `lt`, `lte`,
`exists`, `contains`, `all`. An invalid operator returns a `400` with a
`validOperators` list — the SDK surfaces this as
`FormeError.validation(details:)`.

## Typed field access

`entry.fields` is `[String: FormeValue]`. Use the convenience accessors to
extract native Swift types:

```swift
entry.fields["title"]?.stringValue      // String?
entry.fields["viewCount"]?.intValue     // Int?
entry.fields["published"]?.boolValue    // Bool?
entry.fields["tags"]?.arrayValue        // [FormeValue]?
entry.fields["author"]?.linkID          // String? — the "id" of a reference

// Localized shortText:
entry.fields["title"]?.objectValue?["en-US"]?.stringValue
```

For compile-time safety against your content schema, the `forme typegen` CLI
(coming with CON-69) will generate typed `Codable` structs from your models.

## Configuration

```swift
let config = FormeConfiguration(
    apiKey: "ce_secret_...",
    baseURL: URL(string: "https://management.forme.sh")!,
    defaultLocale: "en-US",         // applied automatically to every list/get
    timeoutSeconds: 15,             // per-request timeout (default: 30s)
    extraHeaders: [                 // sent on every request (e.g. for tracing)
        "X-Forme-Trace-Id": "abc-123"
    ]
)
let client = FormeClient(configuration: config)
```

## Error handling

All SDK methods throw `FormeError`:

```swift
do {
    _ = try await client.entries.get(id: "missing")
} catch FormeError.notFound(let resource, let id) {
    print("\(resource) \(id ?? "") not found")
} catch FormeError.unauthorized {
    // API key revoked or wrong type
} catch FormeError.rateLimited(let retryAfter) {
    // Retry after `retryAfter` seconds if provided. Both numeric ("60")
    // and HTTP-date ("Wed, 21 Oct 2025 07:28:00 GMT") forms are parsed
    // per RFC 7231.
} catch FormeError.preconditionFailed(let currentEtag) {
    // Someone else patched this entry — re-fetch and retry
} catch FormeError.cancelled {
    // The Task was cancelled — typical SwiftUI flow when a view disappears
} catch FormeError.validation(let details) {
    for detail in details {
        print("\(detail.field): \(detail.message)")
    }
}
```

## Notes on PATCH semantics

PATCH bodies are sent with `Content-Type: application/merge-patch+json`. The
Forme API also accepts `application/json` so this is purely informational, but
some upstream proxies (corporate gateways, WAFs) may need a content-type
allow-list updated.

## Notes on key-type checking

The SDK does not validate the key prefix at runtime (`ce_secret_...` vs
`ce_read_...`). Calls that require a specific key type surface any mismatch
as `FormeError.unauthorized` from the server. The server is the authoritative
source for key validity and lifecycle; mirroring that logic in the SDK would
add a brittle allow-list that ages poorly as token formats evolve.

## Development

```bash
# Build
swift build

# Run tests (uses swift-testing — no Xcode required)
swift test

# Strict concurrency (matches CI)
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

## License

MIT © Forme
