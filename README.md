# Forme Swift SDK

Official Swift SDK for [Forme](https://forme.build), the AI-native headless CMS.

**Native async/await, strict Sendable, zero third-party dependencies.**

- ✨ Swift 5.9+ / iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+
- 🚀 Modern async/await throughout — no callbacks, no Combine
- 🛡️ `Sendable`-correct under Swift 6 strict concurrency
- 📦 `URLSession` only — no Alamofire, no third-party networking deps
- 🎯 Full Delivery + Management API coverage
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

let entries = try await client.entries.listDelivery(contentModelId: "blogPost", limit: 10)
for entry in entries.items {
    let title = entry.fields["title"]?.stringValue ?? "Untitled"
    print(title)
}
```

> **Security:** never ship a Secret Key (`ce_secret_...`) in a published iOS
> binary. Use a Read Key (`ce_read_...`) for read-only Delivery access, or
> proxy Management API calls through your own backend.

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
    id: created.id,
    PatchEntryInput(fields: ["title": .object(["en-US": .string("Hello, world")])])
)

// Publish
_ = try await mgmt.entries.publish(id: created.id)
```

## Field filtering

The Delivery API supports rich filtering via the `fields` parameter:

```swift
// Equality (the 80% case)
let post = try await client.entries.listDelivery(
    contentModelId: "blogPost",
    fields: ["slug": .value(.string("my-post"))],
    limit: 1
).items.first

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
    // Retry after `retryAfter` seconds if provided
} catch FormeError.preconditionFailed(let currentEtag) {
    // Someone else patched this entry — re-fetch and retry
} catch FormeError.validation(let details) {
    for detail in details {
        print("\(detail.field): \(detail.message)")
    }
}
```

## Optimistic concurrency (PATCH)

PATCH is available on entries and assets. The server returns an `ETag` header;
pass it as `ifMatch` on the next write to detect stale updates:

```swift
let entry = try await mgmt.entries.patch(id: "abc", PatchEntryInput(fields: ["slug": .string("v1")]))
// ...some time later, on a different tab/device...
do {
    _ = try await mgmt.entries.patch(
        id: "abc",
        PatchEntryInput(fields: ["slug": .string("v2")]),
        ifMatch: "W/\"stale-etag\""
    )
} catch FormeError.preconditionFailed {
    // Refresh and retry
}
```

## Development

```bash
# Build
swift build

# Run tests (uses swift-testing — no Xcode required)
swift test
```

## License

MIT © Forme
