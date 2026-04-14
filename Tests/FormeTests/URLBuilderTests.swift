import Testing
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
