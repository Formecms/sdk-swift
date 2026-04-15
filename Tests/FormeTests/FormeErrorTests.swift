import Testing
import Foundation
@testable import Forme

@Suite("FormeError — typed SDK errors")
struct FormeErrorTests {
    @Test func networkErrorDescription() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Connection refused",
        ])
        let err = FormeError.network(underlying: underlying)
        #expect(err.errorDescription?.contains("Connection refused") == true)
    }

    @Test func httpErrorWithAPIErrorMessage() {
        let api = APIError(code: "VALIDATION", message: "Invalid slug")
        let err = FormeError.http(status: 400, apiError: api)
        #expect(err.errorDescription == "HTTP 400: Invalid slug")
    }

    @Test func httpErrorWithoutAPIError() {
        let err = FormeError.http(status: 500, apiError: nil)
        #expect(err.errorDescription == "HTTP 500")
    }

    @Test func notFoundErrorIncludesResource() {
        let err = FormeError.notFound(resource: "Entry", id: "abc-123")
        #expect(err.errorDescription?.contains("Entry") == true)
        #expect(err.errorDescription?.contains("abc-123") == true)
    }

    @Test func rateLimitedErrorWithRetry() {
        let err = FormeError.rateLimited(retryAfter: 30)
        #expect(err.errorDescription?.contains("30") == true)
    }

    @Test func validationErrorListsDetails() {
        let err = FormeError.validation(details: [
            APIErrorDetail(field: "slug", message: "required"),
            APIErrorDetail(field: "title", message: "too long"),
        ])
        let desc = err.errorDescription ?? ""
        #expect(desc.contains("slug"))
        #expect(desc.contains("title"))
    }

    @Test func cancelledErrorDescription() {
        let err = FormeError.cancelled
        #expect(err.errorDescription == "Request was cancelled")
    }

    @Test func mapURLSessionErrorMapsCancellationToFormeError() {
        // SwiftUI-driven apps cancel tasks when a view disappears. URLSession
        // surfaces this as NSURLErrorCancelled in NSURLErrorDomain. The SDK
        // must translate that to FormeError.cancelled so callers can branch.
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        guard case .cancelled = mapURLSessionError(cancelled) else {
            Issue.record("Expected .cancelled")
            return
        }
    }

    @Test func mapURLSessionErrorMapsOtherErrorsToNetwork() {
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        guard case .network = mapURLSessionError(timeout) else {
            Issue.record("Expected .network")
            return
        }
    }

    @Test func apiErrorDecodesValidationDetails() throws {
        let json = """
        {
            "code": "VALIDATION_ERROR",
            "message": "Invalid input",
            "details": [
                {
                    "field": "fields.slug",
                    "message": "Unknown operator 'bogus' for field 'slug'",
                    "validOperators": ["eq", "ne", "in", "nin"]
                }
            ]
        }
        """.data(using: .utf8)!
        let err = try JSONDecoder().decode(APIError.self, from: json)
        #expect(err.code == "VALIDATION_ERROR")
        #expect(err.details?.count == 1)
        #expect(err.details?.first?.validOperators?.contains("eq") == true)
    }
}
