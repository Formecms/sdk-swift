import Testing
import Foundation
@testable import Forme

@Suite("EntryActionsNamespace — Intelligent Actions via MockTransport")
struct IntelligentActionsTests {
    // MARK: - Helpers

    private func rewriteResultJSON(
        outputValue: String = "Polished title",
        auditId: String = "audit-1"
    ) -> String {
        """
        {
            "outputValue": "\(outputValue)",
            "auditId": "\(auditId)",
            "model": "claude-haiku-4-5",
            "provider": "anthropic",
            "tokensIn": 100,
            "tokensOut": 42,
            "latencyMs": 850,
            "retried": false
        }
        """
    }

    private func decisionResultJSON(
        auditId: String = "audit-1",
        status: String = "approved"
    ) -> String {
        """
        {
            "ok": true,
            "auditId": "\(auditId)",
            "approvalStatus": "\(status)",
            "decidedAt": "2026-04-20T12:00:00.000Z"
        }
        """
    }

    private func errorJSON(code: String, message: String) -> String {
        """
        {"error": {"code": "\(code)", "message": "\(message)"}}
        """
    }

    // MARK: - Rewrite

    @Test func rewriteHappyPath() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(rewriteResultJSON()))
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.actions.rewrite(
            entryId: "entry-1",
            input: RewriteEntryInput(fieldName: "title", tone: .formal)
        )

        #expect(response.value.outputValue == "Polished title")
        #expect(response.value.auditId == "audit-1")
        #expect(response.value.model == "claude-haiku-4-5")
        #expect(response.value.tokensIn == 100)
        #expect(response.value.tokensOut == 42)
        #expect(response.value.latencyMs == 850)
        #expect(response.value.retried == false)

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        let url = request.url?.absoluteString ?? ""
        #expect(url.contains("/management/entries/entry-1/actions/rewrite"))

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["fieldName"] as? String == "title")
        #expect(json?["tone"] as? String == "formal")
    }

    @Test func rewriteWithLocale() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(rewriteResultJSON()))
        let client = makeTestClient(transport: transport)

        _ = try await client.entries.actions.rewrite(
            entryId: "entry-1",
            input: RewriteEntryInput(fieldName: "tagline", tone: .casual, locale: "de-DE")
        )

        let body = try #require(transport.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["locale"] as? String == "de-DE")
    }

    @Test func rewriteRateLimitedThrows() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(
            errorJSON(code: "RATE_LIMITED", message: "Too many requests"),
            statusCode: 429
        ))
        let client = makeTestClient(transport: transport)

        do {
            _ = try await client.entries.actions.rewrite(
                entryId: "entry-1",
                input: RewriteEntryInput(fieldName: "title", tone: .formal)
            )
            Issue.record("Expected FormeError.rateLimited")
        } catch let error as FormeError {
            guard case .rateLimited = error else {
                Issue.record("Expected rateLimited, got \(error)")
                return
            }
        }
    }

    @Test func rewriteValidationErrorThrows() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(
            """
            {"error": {"code": "VALIDATION_ERROR", "details": [{"field": "fieldName", "message": "unknown field"}]}}
            """,
            statusCode: 400
        ))
        let client = makeTestClient(transport: transport)

        do {
            _ = try await client.entries.actions.rewrite(
                entryId: "entry-1",
                input: RewriteEntryInput(fieldName: "bad", tone: .formal)
            )
            Issue.record("Expected FormeError.validation")
        } catch let error as FormeError {
            guard case .validation(let details) = error else {
                Issue.record("Expected validation, got \(error)")
                return
            }
            #expect(details.first?.field == "fieldName")
        }
    }

    @Test func rewriteProviderErrorThrows() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(
            errorJSON(code: "PROVIDER_ERROR", message: "Upstream timeout"),
            statusCode: 502
        ))
        let client = makeTestClient(transport: transport)

        do {
            _ = try await client.entries.actions.rewrite(
                entryId: "entry-1",
                input: RewriteEntryInput(fieldName: "title", tone: .formal)
            )
            Issue.record("Expected FormeError.http")
        } catch let error as FormeError {
            guard case .http(let status, _) = error else {
                Issue.record("Expected http, got \(error)")
                return
            }
            #expect(status == 502)
        }
    }

    // MARK: - Approve

    @Test func approveHappyPath() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(decisionResultJSON()))
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.actions.approve(
            entryId: "entry-1",
            auditId: "audit-1"
        )

        #expect(response.value.ok == true)
        #expect(response.value.approvalStatus == "approved")

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "POST")
        let url = request.url?.absoluteString ?? ""
        #expect(url.contains("/management/entries/entry-1/actions/audit-1/approve"))
    }

    // MARK: - Discard

    @Test func discardHappyPath() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(decisionResultJSON(status: "discarded")))
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.actions.discard(
            entryId: "entry-1",
            auditId: "audit-1"
        )

        #expect(response.value.ok == true)
        #expect(response.value.approvalStatus == "discarded")

        let request = try #require(transport.lastRequest)
        let url = request.url?.absoluteString ?? ""
        #expect(url.contains("/actions/audit-1/discard"))
    }

    @Test func approveAlreadyDecidedThrows409() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(
            errorJSON(code: "ALREADY_DECIDED", message: "Action already decided"),
            statusCode: 409
        ))
        let client = makeTestClient(transport: transport)

        do {
            _ = try await client.entries.actions.approve(
                entryId: "entry-1",
                auditId: "audit-1"
            )
            Issue.record("Expected FormeError.http(409)")
        } catch let error as FormeError {
            guard case .http(let status, let apiError) = error else {
                Issue.record("Expected http, got \(error)")
                return
            }
            #expect(status == 409)
            #expect(apiError?.code == "ALREADY_DECIDED")
        }
    }

    // MARK: - Cancellation

    @Test func rewriteCancellationThrows() async throws {
        let transport = MockTransport()
        transport.enqueue(.raw(rewriteResultJSON()))
        let client = makeTestClient(transport: transport)

        let task = Task {
            try await client.entries.actions.rewrite(
                entryId: "entry-1",
                input: RewriteEntryInput(fieldName: "title", tone: .formal)
            )
        }
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // expected
        } catch let error as FormeError {
            guard case .cancelled = error else {
                Issue.record("Expected cancelled, got \(error)")
                return
            }
        }
    }

    // MARK: - Optional field decoding

    @Test func rewriteDecodesOptionalCacheTokens() async throws {
        let transport = MockTransport()
        let json = """
        {
            "outputValue": "Cached output",
            "auditId": "audit-2",
            "model": "claude-haiku-4-5",
            "provider": "anthropic",
            "tokensIn": 50,
            "tokensOut": 20,
            "latencyMs": 100,
            "retried": true,
            "cacheReadTokens": 30,
            "cacheCreationTokens": 10
        }
        """
        transport.enqueue(.raw(json))
        let client = makeTestClient(transport: transport)

        let response = try await client.entries.actions.rewrite(
            entryId: "entry-1",
            input: RewriteEntryInput(fieldName: "title", tone: .technical)
        )

        #expect(response.value.cacheReadTokens == 30)
        #expect(response.value.cacheCreationTokens == 10)
        #expect(response.value.retried == true)
    }

    // MARK: - AI Usage

    @Test func aiUsageHappyPath() async throws {
        let transport = MockTransport()
        let json = """
        {
            "monthly": {
                "total": 42,
                "approved": 30,
                "discarded": 10,
                "tokensIn": 5000,
                "tokensOut": 2000
            },
            "rateWindow": {
                "requestCount": 15,
                "effectiveCount": 15,
                "limit": 60,
                "windowEnd": "2026-04-20T12:01:00.000Z"
            }
        }
        """
        transport.enqueue(.raw(json))
        let client = makeTestClient(transport: transport)

        let response = try await client.workspace.aiUsage()

        #expect(response.value.monthly.total == 42)
        #expect(response.value.monthly.approved == 30)
        #expect(response.value.monthly.tokensIn == 5000)
        #expect(response.value.rateWindow?.effectiveCount == 15)
        #expect(response.value.rateWindow?.limit == 60)

        let request = try #require(transport.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString.contains("/management/workspace/ai-usage") == true)
    }

    @Test func aiUsageNullRateWindow() async throws {
        let transport = MockTransport()
        let json = """
        {
            "monthly": {
                "total": 0,
                "approved": 0,
                "discarded": 0,
                "tokensIn": 0,
                "tokensOut": 0
            },
            "rateWindow": null
        }
        """
        transport.enqueue(.raw(json))
        let client = makeTestClient(transport: transport)

        let response = try await client.workspace.aiUsage()

        #expect(response.value.monthly.total == 0)
        #expect(response.value.rateWindow == nil)
    }
}
