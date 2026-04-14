import Foundation

/// Serialize a query parameter map into a URL-safe query string.
///
/// Handles the Forme filter DSL: when a `fields` key is a dictionary, its
/// entries are expanded into `fields.{apiId}[{op}]=value` form.
///
/// ```swift
/// buildQuery(["limit": 20, "fields": ["slug": "my-post"]])
/// // → "?limit=20&fields.slug=my-post"
///
/// buildQuery(["fields": ["viewCount": ["gte": 100]]])
/// // → "?fields.viewCount[gte]=100"
///
/// buildQuery(["fields": ["tags": ["in": ["ai", "ml"]]]])
/// // → "?fields.tags[in]=ai,ml"
/// ```
func buildQuery(_ params: [String: QueryValue]) -> String {
    var items: [URLQueryItem] = []

    for key in params.keys.sorted() {
        guard let value = params[key] else { continue }
        appendQueryItems(key: key, value: value, into: &items)
    }

    guard !items.isEmpty else { return "" }

    var components = URLComponents()
    components.queryItems = items
    return "?" + (components.percentEncodedQuery ?? "")
}

/// A serializable query parameter value. Keeps the type closed so we don't
/// accidentally stringify `Any` values that won't round-trip cleanly.
enum QueryValue: Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case fields([String: FieldFilter])
}

/// A per-field filter value: either a direct equality shorthand or an
/// operator map.
///
/// ```swift
/// // Equality:
/// try await client.entries.list(fields: ["slug": .value(.string("my-post"))])
///
/// // Operator:
/// try await client.entries.list(fields: ["viewCount": .operators(["gte": .int(100)])])
///
/// // List ("in"):
/// try await client.entries.list(fields: ["tags": .operators(["in": .array(["ai", "ml"])])])
/// ```
public enum FieldFilter: Sendable {
    case value(QueryScalar)
    case operators([String: QueryScalar])
}

/// A scalar value suitable for URL encoding within a field filter.
public enum QueryScalar: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([String])
}

// MARK: - Serialization

private func appendQueryItems(
    key: String,
    value: QueryValue,
    into items: inout [URLQueryItem]
) {
    switch value {
    case .string(let s):
        items.append(URLQueryItem(name: key, value: s))
    case .int(let i):
        items.append(URLQueryItem(name: key, value: String(i)))
    case .bool(let b):
        items.append(URLQueryItem(name: key, value: b ? "true" : "false"))
    case .fields(let fields):
        for apiId in fields.keys.sorted() {
            guard let filter = fields[apiId] else { continue }
            appendFieldFilter(apiId: apiId, filter: filter, into: &items)
        }
    }
}

private func appendFieldFilter(
    apiId: String,
    filter: FieldFilter,
    into items: inout [URLQueryItem]
) {
    switch filter {
    case .value(let scalar):
        items.append(URLQueryItem(name: "fields.\(apiId)", value: scalarString(scalar)))
    case .operators(let ops):
        for op in ops.keys.sorted() {
            guard let val = ops[op] else { continue }
            items.append(
                URLQueryItem(name: "fields.\(apiId)[\(op)]", value: scalarString(val))
            )
        }
    }
}

private func scalarString(_ s: QueryScalar) -> String {
    switch s {
    case .string(let v): return v
    case .int(let v): return String(v)
    case .double(let v): return String(v)
    case .bool(let v): return v ? "true" : "false"
    case .array(let v): return v.joined(separator: ",")
    }
}
