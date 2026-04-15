import Foundation

// MARK: - Pagination

/// A paginated list of items returned by list endpoints.
///
/// The custom decoder accepts every shape the Forme API returns:
/// - Delivery API: `{ items, total, limit, offset }`
/// - Management API (paginated): `{ data, pagination: { total, limit, offset } }`
/// - Management API (unpaginated, e.g. environments / locales / api-keys):
///   `{ data }` — `total = data.count`, `limit = data.count`, `offset = 0`
///
/// The public surface (`items`, `total`, `limit`, `offset`) is identical
/// across all three.
public struct PaginatedList<Item: Sendable & Decodable>: Sendable, Decodable {
    public let items: [Item]
    public let total: Int
    public let limit: Int
    public let offset: Int

    public init(items: [Item], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey {
        case items, total, limit, offset, data, pagination
    }

    private struct Pagination: Decodable {
        let total: Int
        let limit: Int
        let offset: Int
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Delivery shape: { items, total, limit, offset }
        if let items = try container.decodeIfPresent([Item].self, forKey: .items) {
            self.items = items
            self.total = try container.decode(Int.self, forKey: .total)
            self.limit = try container.decode(Int.self, forKey: .limit)
            self.offset = try container.decode(Int.self, forKey: .offset)
            return
        }

        // Management shape: { data, pagination? }
        let data = try container.decode([Item].self, forKey: .data)
        if let pag = try container.decodeIfPresent(Pagination.self, forKey: .pagination) {
            self.items = data
            self.total = pag.total
            self.limit = pag.limit
            self.offset = pag.offset
        } else {
            // Unpaginated Management list — synthesize sensible totals.
            self.items = data
            self.total = data.count
            self.limit = data.count
            self.offset = 0
        }
    }
}

// MARK: - Delivery includes

/// Linked entries and assets that the Delivery API returns alongside an
/// entry list when `?include=1` (or higher) is passed. Each linked entity
/// is fully decoded — same shape as its top-level counterpart.
public struct DeliveryIncludes: Sendable, Decodable {
    public let entries: [Entry]
    public let assets: [Asset]

    public init(entries: [Entry] = [], assets: [Asset] = []) {
        self.entries = entries
        self.assets = assets
    }
}

/// Delivery entry-list response with an optional `includes` payload.
///
/// Accessed via `client.entries.listDelivery(include: 1)`. When
/// `include` is omitted (or zero), `includes` is `nil` and only `items`
/// is meaningful.
public struct DeliveryEntryListResponse: Sendable, Decodable {
    public let items: [Entry]
    public let total: Int
    public let limit: Int
    public let offset: Int
    public let includes: DeliveryIncludes?

    public init(
        items: [Entry],
        total: Int,
        limit: Int,
        offset: Int,
        includes: DeliveryIncludes? = nil
    ) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
        self.includes = includes
    }
}

/// Delivery single-entry response with optional `includes` payload.
public struct DeliveryEntryResponse: Sendable, Decodable {
    public let entry: Entry
    public let includes: DeliveryIncludes?

    public init(entry: Entry, includes: DeliveryIncludes? = nil) {
        self.entry = entry
        self.includes = includes
    }

    private enum CodingKeys: String, CodingKey {
        case includes
    }

    public init(from decoder: Decoder) throws {
        // The single-entry endpoint returns the entry as the top-level
        // object with an optional sibling `includes` field. Decode the
        // entry from the same container and lift `includes` out separately.
        self.entry = try Entry(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.includes = try container.decodeIfPresent(DeliveryIncludes.self, forKey: .includes)
    }
}

// MARK: - Content Model

/// A content model — the schema for a collection of entries.
public struct ContentModel: Sendable, Codable {
    public let id: String
    public let accountId: String?
    public let workspaceId: String?
    public let environmentId: String?
    public let apiId: String
    public let name: String
    public let description: String?
    public let type: String
    public let fields: [FieldDef]
    public let entryCount: Int?
    public let createdAt: Date
    public let updatedAt: Date
}

/// A single field definition within a content model. Schema varies by type
/// so type-specific constraints are exposed as `FormeValue`.
public struct FieldDef: Sendable, Codable {
    public let apiId: String
    public let name: String
    public let type: String
    public let description: String?
    public let required: Bool?
    public let localized: Bool?

    /// Additional type-specific fields (minLength, maxLength, pattern, in,
    /// allowedModels, itemType, etc.) captured via FormeValue so any
    /// field-type metadata is preserved round-trip.
    public let extra: [String: FormeValue]

    // Custom coding to capture unknown keys into `extra`.
    private enum StableKeys: String, CodingKey {
        case apiId, name, type, description, required, localized
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let stable = try decoder.container(keyedBy: StableKeys.self)
        self.apiId = try stable.decode(String.self, forKey: .apiId)
        self.name = try stable.decode(String.self, forKey: .name)
        self.type = try stable.decode(String.self, forKey: .type)
        self.description = try stable.decodeIfPresent(String.self, forKey: .description)
        self.required = try stable.decodeIfPresent(Bool.self, forKey: .required)
        self.localized = try stable.decodeIfPresent(Bool.self, forKey: .localized)

        let all = try decoder.container(keyedBy: DynamicKey.self)
        let stableKeys: Set<String> = ["apiId", "name", "type", "description", "required", "localized"]
        var extra: [String: FormeValue] = [:]
        for key in all.allKeys where !stableKeys.contains(key.stringValue) {
            extra[key.stringValue] = try all.decode(FormeValue.self, forKey: key)
        }
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var stable = encoder.container(keyedBy: StableKeys.self)
        try stable.encode(apiId, forKey: .apiId)
        try stable.encode(name, forKey: .name)
        try stable.encode(type, forKey: .type)
        try stable.encodeIfPresent(description, forKey: .description)
        try stable.encodeIfPresent(required, forKey: .required)
        try stable.encodeIfPresent(localized, forKey: .localized)

        var dynamic = encoder.container(keyedBy: DynamicKey.self)
        for (key, value) in extra {
            if let k = DynamicKey(stringValue: key) {
                try dynamic.encode(value, forKey: k)
            }
        }
    }
}

// MARK: - Entry

/// An entry — a single row of content conforming to a content model.
public struct Entry: Sendable, Decodable {
    public let id: String
    public let contentModel: ContentModelRef?
    public let contentModelId: String?
    public let status: String?
    public let fields: [String: FormeValue]
    public let publishedFields: [String: FormeValue]?
    public let publishedVersion: Int?
    public let firstPublishedAt: Date?
    public let publishedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
    public let sys: Sys?

    public struct Sys: Sendable, Decodable {
        public let locale: String?
    }
}

/// Reference to a content model (as embedded in Delivery API responses).
public struct ContentModelRef: Sendable, Decodable {
    public let id: String
    public let apiId: String
}

/// A snapshot of an entry's fields at publish time.
public struct EntryVersion: Sendable, Decodable {
    public let id: String
    public let entryId: String
    public let version: Int
    public let fields: [String: FormeValue]
    public let publishedAt: Date
    public let sys: Entry.Sys?
}

// MARK: - Asset

public struct Asset: Sendable, Decodable {
    public let id: String
    public let accountId: String?
    public let workspaceId: String?
    public let environmentId: String?
    public let filename: String
    public let mimeType: String
    public let sizeBytes: Int64
    public let title: String?
    public let description: String?
    public let alt: String?
    public let url: String?
    public let status: String?
    public let publishedVersion: Int?
    public let firstPublishedAt: Date?
    public let publishedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
    public let sys: Entry.Sys?
}

/// A snapshot of an asset's metadata at publish time.
public struct AssetVersion: Sendable, Decodable {
    public let id: String
    public let assetId: String
    public let version: Int
    public let filename: String
    public let mimeType: String
    public let sizeBytes: Int64
    public let title: String?
    public let description: String?
    public let alt: String?
    public let publishedAt: Date
}

// MARK: - Environment

public struct Environment: Sendable, Codable {
    public let id: String
    public let accountId: String?
    public let workspaceId: String?
    public let name: String
    public let slug: String
    public let isMaster: Bool
    public let sourceEnvironmentId: String?
    public let createdAt: Date
    public let updatedAt: Date
}

// MARK: - Locale

public struct Locale: Sendable, Codable {
    public let id: String
    public let accountId: String?
    public let workspaceId: String?
    public let code: String
    public let name: String
    public let isDefault: Bool
    public let fallbackLocaleId: String?
    public let createdAt: Date
    public let updatedAt: Date
}

// MARK: - Workspace

public struct Workspace: Sendable, Decodable {
    public let id: String
    public let accountId: String
    public let accountName: String
    public let name: String
    public let slug: String
    public let createdAt: Date
    public let updatedAt: Date
}

// MARK: - API Key

public struct APIKey: Sendable, Decodable {
    public let id: String
    public let accountId: String
    public let workspaceId: String
    public let environmentId: String
    public let label: String?
    public let keyHint: String
    public let keyType: String
    public let prefix: String
    public let revokedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
}

// MARK: - Input types

/// Input for creating a new content model.
public struct CreateContentModelInput: Sendable, Encodable {
    public let apiId: String
    public let name: String
    public let description: String?
    public let type: String?
    public let fields: [FieldDef]

    public init(apiId: String, name: String, description: String? = nil, type: String? = nil, fields: [FieldDef]) {
        self.apiId = apiId
        self.name = name
        self.description = description
        self.type = type
        self.fields = fields
    }
}

/// Input for updating a content model.
public struct UpdateContentModelInput: Sendable, Encodable {
    public let name: String?
    public let description: String?
    public let type: String?
    public let fields: [FieldDef]?

    public init(name: String? = nil, description: String? = nil, type: String? = nil, fields: [FieldDef]? = nil) {
        self.name = name
        self.description = description
        self.type = type
        self.fields = fields
    }
}

/// Input for creating a new entry.
public struct CreateEntryInput: Sendable, Encodable {
    public let contentModelId: String
    public let fields: [String: FormeValue]

    public init(contentModelId: String, fields: [String: FormeValue]) {
        self.contentModelId = contentModelId
        self.fields = fields
    }
}

/// Input for updating (PUT — full replacement) an entry's fields.
public struct UpdateEntryInput: Sendable, Encodable {
    public let fields: [String: FormeValue]

    public init(fields: [String: FormeValue]) {
        self.fields = fields
    }
}

/// Input for patching (PATCH — shallow merge) an entry's fields.
/// Omit a key to preserve; send `FormeValue.null` to clear.
public struct PatchEntryInput: Sendable, Encodable {
    public let fields: [String: FormeValue]

    public init(fields: [String: FormeValue]) {
        self.fields = fields
    }
}

/// Input for updating asset metadata.
public struct UpdateAssetInput: Sendable, Encodable {
    public let title: String?
    public let description: String?
    public let alt: String?

    public init(title: String? = nil, description: String? = nil, alt: String? = nil) {
        self.title = title
        self.description = description
        self.alt = alt
    }
}

/// Input for creating a new environment.
public struct CreateEnvironmentInput: Sendable, Encodable {
    public let name: String
    public let slug: String

    public init(name: String, slug: String) {
        self.name = name
        self.slug = slug
    }
}

/// Input for updating an environment.
public struct UpdateEnvironmentInput: Sendable, Encodable {
    public let name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}

/// Input for creating a new locale.
public struct CreateLocaleInput: Sendable, Encodable {
    public let code: String
    public let name: String
    public let isDefault: Bool?
    public let fallbackLocaleId: String?

    public init(code: String, name: String, isDefault: Bool? = nil, fallbackLocaleId: String? = nil) {
        self.code = code
        self.name = name
        self.isDefault = isDefault
        self.fallbackLocaleId = fallbackLocaleId
    }
}

/// Input for updating a locale.
public struct UpdateLocaleInput: Sendable, Encodable {
    public let name: String?
    public let isDefault: Bool?
    public let fallbackLocaleId: String?

    public init(name: String? = nil, isDefault: Bool? = nil, fallbackLocaleId: String? = nil) {
        self.name = name
        self.isDefault = isDefault
        self.fallbackLocaleId = fallbackLocaleId
    }
}

/// Input for updating workspace metadata.
public struct UpdateWorkspaceInput: Sendable, Encodable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
