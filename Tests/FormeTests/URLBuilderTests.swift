import Testing
import Foundation
@testable import Forme

@Suite("buildQuery — URL parameter serialization with Forme filter DSL")
struct URLBuilderTests {
    @Test func emptyParamsReturnsEmptyString() {
        #expect(buildQuery([:]) == "")
    }

    @Test func simpleScalarParams() {
        let out = buildQuery(["limit": .int(20), "offset": .int(0)])
        // Keys are sorted for deterministic output
        #expect(out.contains("limit=20"))
        #expect(out.contains("offset=0"))
        #expect(out.hasPrefix("?"))
    }

    @Test func stringParam() {
        let out = buildQuery(["locale": .string("en-US")])
        #expect(out == "?locale=en-US")
    }

    @Test func boolParamSerializedAsTrueFalse() {
        let out = buildQuery(["active": .bool(true)])
        #expect(out == "?active=true")
    }

    @Test func fieldFilterEqualityShorthand() {
        let out = buildQuery([
            "fields": .fields(["slug": .value(.string("my-post"))]),
        ])
        #expect(out == "?fields.slug=my-post")
    }

    @Test func fieldFilterOperator() {
        let out = buildQuery([
            "fields": .fields(["viewCount": .operators(["gte": .int(100)])]),
        ])
        #expect(out == "?fields.viewCount%5Bgte%5D=100")
    }

    @Test func fieldFilterInListCommaSeparated() {
        let out = buildQuery([
            "fields": .fields([
                "tags": .operators(["in": .array(["ai", "ml"])]),
            ]),
        ])
        #expect(out == "?fields.tags%5Bin%5D=ai,ml")
    }

    @Test func mixedScalarAndFieldFilters() {
        let out = buildQuery([
            "limit": .int(10),
            "fields": .fields(["slug": .value(.string("my-post"))]),
        ])
        #expect(out.contains("limit=10"))
        #expect(out.contains("fields.slug=my-post"))
    }

    @Test func specialCharsInValueAreEncoded() {
        let out = buildQuery(["q": .string("hello world & stuff")])
        // URLComponents handles percent-encoding
        #expect(out.contains("hello%20world") || out.contains("hello+world"))
        #expect(out.contains("%26"))
    }
}

@Suite("URL.appendingRelative — base URL + relative path concatenation")
struct AppendingRelativeTests {
    @Test func baseWithoutPathAndPathWithLeadingSlash() {
        let base = URL(string: "https://api.forme.sh")!
        let result = base.appendingRelative("/management/entries")
        #expect(result.absoluteString == "https://api.forme.sh/management/entries")
    }

    @Test func baseWithTrailingSlashAndPathWithLeadingSlashDedup() {
        let base = URL(string: "https://api.forme.sh/")!
        let result = base.appendingRelative("/management/entries")
        #expect(result.absoluteString == "https://api.forme.sh/management/entries")
    }

    @Test func baseWithoutSlashAndPathWithoutSlashInsertsSeparator() {
        let base = URL(string: "https://api.forme.sh")!
        let result = base.appendingRelative("management/entries")
        #expect(result.absoluteString == "https://api.forme.sh/management/entries")
    }

    @Test func baseWithSubpathPlusRelativePathConcatenates() {
        let base = URL(string: "https://api.forme.sh/v1")!
        let result = base.appendingRelative("/entries/abc")
        #expect(result.absoluteString == "https://api.forme.sh/v1/entries/abc")
    }

    @Test func emptyPathReturnsBaseUnchanged() {
        let base = URL(string: "https://api.forme.sh/v1")!
        let result = base.appendingRelative("")
        #expect(result.absoluteString == "https://api.forme.sh/v1")
    }

    @Test func pathWithQueryStringSplitsCorrectly() {
        let base = URL(string: "https://api.forme.sh")!
        let result = base.appendingRelative("/entries?limit=10&offset=20")
        #expect(result.absoluteString == "https://api.forme.sh/entries?limit=10&offset=20")
    }

    @Test func nestedPathPreserved() {
        let base = URL(string: "https://api.forme.sh")!
        let result = base.appendingRelative("/management/entries/abc/versions")
        #expect(result.absoluteString == "https://api.forme.sh/management/entries/abc/versions")
    }

    @Test func queryWithPercentEncodedValues() {
        let base = URL(string: "https://api.forme.sh")!
        let result = base.appendingRelative("/entries?fields.slug=my%20post")
        // Stored as percentEncodedQuery — survives round-trip without re-encoding.
        #expect(result.absoluteString == "https://api.forme.sh/entries?fields.slug=my%20post")
    }
}

@Suite("encodePathComponent — defensive percent-encoding for path interpolation")
struct EncodePathComponentTests {
    @Test func uuidPassesThroughUnchanged() {
        let id = "550e8400-e29b-41d4-a716-446655440000"
        #expect(encodePathComponent(id) == id)
    }

    @Test func slashIsEscaped() {
        // A `/` in a path component would otherwise smuggle an extra segment.
        #expect(encodePathComponent("foo/bar") == "foo%2Fbar")
    }

    @Test func questionMarkIsEscaped() {
        #expect(encodePathComponent("foo?x=1") == "foo%3Fx=1")
    }

    @Test func percentIsEscaped() {
        #expect(encodePathComponent("100%") == "100%25")
    }

    @Test func unicodeIsEscaped() {
        // RFC 3986 reserves non-ASCII for percent-encoding.
        #expect(encodePathComponent("café") == "caf%C3%A9")
    }
}
