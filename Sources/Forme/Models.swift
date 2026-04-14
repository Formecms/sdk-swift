import Foundation

// MARK: - Pagination

/// A paginated list of items returned by list endpoints.
public struct PaginatedList<Item: Sendable & Decodable>: Sendable, Decodable {
    public let items: [Item]
    public let total: Int
    public let limit: Int
    public let offset: Int
}

/// Management API returns lists as `{data, pagination}` envelope.
public struct ManagementList<Item: Sendable & Decodable>: Sendable, Decodable {
    public let data: [Item]
    public let pagination: Pagination

    public struct Pagination: Sendable, Decodable {
        public let total: Int
        public let limit: Int
        public let offset: Int
    }

    /// Convert to the `PaginatedList` shape for a uniform public API.
    var asPaginated: PaginatedList<Item> {
        // Keeping this as an internal helper — callers see `PaginatedList` only.
        fatalError("Use ManagementList.toPaginated()")
    }

    func toPaginated() -> PaginatedListMgmt<Item> {
        PaginatedListMgmt(items: data, total: pagination.total, limit: pagination.limit, offset: pagination.offset)
    }
}

/// Public paginated shape for Management responses (same fields as
/// `PaginatedList` but constructed from the `{data, pagination}` envelope).
public struct PaginatedListMgmt<Item: Sendable & Decodable>: Sendable {
    public let items: [Item]
    public let total: Int
    public let limit: Int
    public let offset: Int
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
