import Foundation

/// A dynamic value stored in a Forme entry field.
///
/// Entry fields are schema-driven and their TypeScript equivalent is
/// `Record<string, unknown>`. Swift's strict concurrency model makes
/// `[String: Any]` infeasible (not `Sendable`), so `FormeValue` is a sealed
/// enum that preserves full type fidelity while staying `Sendable` and
/// `Codable`.
///
/// For type-safe access to known content models, use the generic
/// `Entry<T>` variant with your own `Codable` struct:
///
/// ```swift
/// struct BlogPost: Codable, Sendable {
///     let title: String
///     let slug: String
/// }
/// let entry: Entry<BlogPost> = try await client.entries.get(id: id, as: BlogPost.self)
/// ```
///
/// For ad-hoc access, use the untyped accessors:
///
/// ```swift
/// let title = entry.fields["title"]?.stringValue ?? "Untitled"
/// let tags = entry.fields["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
/// ```
public enum FormeValue: Sendable, Codable, Hashable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([FormeValue])
    case object([String: FormeValue])
    case null

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        // Try Int64 before Double — Swift's Double can lose precision for large
        // integers. JSON numbers without decimals come through as integers.
        if let i = try? container.decode(Int64.self) {
            self = .int(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        if let arr = try? container.decode([FormeValue].self) {
            self = .array(arr)
            return
        }
        if let obj = try? container.decode([String: FormeValue].self) {
            self = .object(obj)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    // MARK: - Convenience accessors

    /// Returns the string value if this is `.string`, else `nil`.
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Returns the integer value if this is `.int`, else `nil`.
    public var intValue: Int? {
        if case .int(let i) = self { return Int(i) }
        return nil
    }

    /// Returns the double value if this is `.double` (falling back to `.int`
    /// → Double), else `nil`.
    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    /// Returns the boolean value if this is `.bool`, else `nil`.
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Returns the array of values if this is `.array`, else `nil`.
    public var arrayValue: [FormeValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Returns the object (string-keyed map) if this is `.object`, else `nil`.
    public var objectValue: [String: FormeValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Returns true if this value is `.null`.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Returns a link-style object's `id` when the value is `.object` with a
    /// string `id` field (reference and asset field shape). Useful for
    /// `entry.fields["author"]?.linkID`.
    public var linkID: String? {
        if case .object(let obj) = self, case .string(let id) = obj["id"] {
            return id
        }
        return nil
    }
}
