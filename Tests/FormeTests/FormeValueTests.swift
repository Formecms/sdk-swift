import Testing
import Foundation
@testable import Forme

@Suite("FormeValue — dynamic entry field values")
struct FormeValueTests {
    // MARK: - Codable round-trip

    @Test func stringRoundTrip() throws {
        let v = FormeValue.string("hello")
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(FormeValue.self, from: data)
        #expect(decoded == v)
    }

    @Test func intRoundTrip() throws {
        let v = FormeValue.int(42)
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(FormeValue.self, from: data)
        #expect(decoded == v)
    }

    @Test func doubleRoundTrip() throws {
        let v = FormeValue.double(3.14)
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(FormeValue.self, from: data)
        #expect(decoded == v)
    }

    @Test func boolRoundTrip() throws {
        let v = FormeValue.bool(true)
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(FormeValue.self, from: data)
        #expect(decoded == v)
    }

    @Test func nullRoundTrip() throws {
        let data = "null".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FormeValue.self, from: data)
        #expect(decoded == .null)
    }

    @Test func arrayRoundTrip() throws {
        let v = FormeValue.array([.string("a"), .int(1), .bool(false), .null])
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(FormeValue.self, from: data)
        #expect(decoded == v)
    }

    @Test func objectRoundTrip() throws {
        let v = FormeValue.object([
            "title": .string("Hello"),
            "count": .int(5),
            "active": .bool(true),
        ])
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(FormeValue.self, from: data)
        #expect(decoded == v)
    }

    @Test func nestedObjectDecode() throws {
        let json = """
        {"author": {"id": "abc-123"}, "tags": ["ai", "ml"]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([String: FormeValue].self, from: json)
        #expect(decoded["author"]?.linkID == "abc-123")
        #expect(decoded["tags"]?.arrayValue?.count == 2)
        #expect(decoded["tags"]?.arrayValue?.first?.stringValue == "ai")
    }

    // MARK: - Accessors

    @Test func stringAccessor() {
        #expect(FormeValue.string("x").stringValue == "x")
        #expect(FormeValue.int(1).stringValue == nil)
    }

    @Test func intAccessor() {
        #expect(FormeValue.int(42).intValue == 42)
        #expect(FormeValue.string("x").intValue == nil)
    }

    @Test func doubleAccessorUpcastsInt() {
        #expect(FormeValue.int(42).doubleValue == 42.0)
        #expect(FormeValue.double(3.14).doubleValue == 3.14)
    }

    @Test func boolAccessor() {
        #expect(FormeValue.bool(true).boolValue == true)
        #expect(FormeValue.string("true").boolValue == nil)
    }

    @Test func arrayAccessor() {
        let v: FormeValue = .array([.string("a")])
        #expect(v.arrayValue?.count == 1)
        #expect(FormeValue.string("x").arrayValue == nil)
    }

    @Test func objectAccessor() {
        let v: FormeValue = .object(["k": .string("v")])
        #expect(v.objectValue?.count == 1)
        #expect(FormeValue.string("x").objectValue == nil)
    }

    @Test func isNullAccessor() {
        #expect(FormeValue.null.isNull)
        #expect(!FormeValue.string("").isNull)
    }

    @Test func linkIDFromObjectWithStringId() {
        let v: FormeValue = .object(["id": .string("abc")])
        #expect(v.linkID == "abc")
    }

    @Test func linkIDIsNilForNonObjectOrMissingId() {
        #expect(FormeValue.string("x").linkID == nil)
        #expect(FormeValue.object(["id": .int(5)]).linkID == nil)
        #expect(FormeValue.object(["other": .string("x")]).linkID == nil)
    }

    // MARK: - Integer precision

    @Test func largeIntegerPreservesPrecision() throws {
        // 2^53 + 1 — Double can't represent this exactly, Int64 can.
        let big = Int64(9_007_199_254_740_993)
        let json = "\(big)".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FormeValue.self, from: json)
        guard case .int(let i) = decoded else {
            Issue.record("Expected .int, got \(decoded)")
            return
        }
        #expect(i == big)
    }
}
