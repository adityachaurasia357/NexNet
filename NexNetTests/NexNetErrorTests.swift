//
//  NexNetErrorTests.swift
//  NexNetTests
//
//  Created by Aditya Chaurasia on 22/06/2026.
//

import Testing
import Foundation
@testable import NexNet

@Suite("NexNetError")
struct NexNetErrorTests {

    // MARK: - statusCode

    @Test("HTTP errors carry their status code")
    func httpStatusCodes() {
        #expect(NexNetError.badRequest.statusCode          == 400)
        #expect(NexNetError.unauthorized.statusCode        == 401)
        #expect(NexNetError.forbidden.statusCode           == 403)
        #expect(NexNetError.notFound(url: "").statusCode   == 404)
        #expect(NexNetError.unprocessableEntity.statusCode == 422)
        #expect(NexNetError.tooManyRequests(retryAfter: nil).statusCode   == 429)
        #expect(NexNetError.internalServerError.statusCode == 500)
        #expect(NexNetError.badGateway.statusCode          == 502)
        #expect(NexNetError.serviceUnavailable(retryAfter: nil).statusCode == 503)
        #expect(NexNetError.gatewayTimeout.statusCode      == 504)
        #expect(NexNetError.httpError(statusCode: 418, data: nil).statusCode == 418)
    }

    @Test("Non-HTTP errors return nil statusCode")
    func nonHttpStatusCodes() {
        #expect(NexNetError.invalidURL("x").statusCode == nil)
        #expect(NexNetError.noInternetConnection.statusCode == nil)
        #expect(NexNetError.timeout.statusCode == nil)
        #expect(NexNetError.cancelled.statusCode == nil)
        #expect(NexNetError.emptyResponse.statusCode == nil)
        #expect(NexNetError.decodingFailed(URLError(.unknown), codingPath: "").statusCode == nil)
        #expect(NexNetError.encodingFailed(URLError(.unknown)).statusCode == nil)
        #expect(NexNetError.unknown(URLError(.unknown)).statusCode == nil)
    }

    // MARK: - isRetryable

    @Test("Transient errors are retryable")
    func retryable() {
        #expect(NexNetError.timeout.isRetryable)
        #expect(NexNetError.noInternetConnection.isRetryable)
        #expect(NexNetError.internalServerError.isRetryable)
        #expect(NexNetError.badGateway.isRetryable)
        #expect(NexNetError.gatewayTimeout.isRetryable)
        #expect(NexNetError.tooManyRequests(retryAfter: nil).isRetryable)
        #expect(NexNetError.serviceUnavailable(retryAfter: "30").isRetryable)
    }

    @Test("Deterministic errors are not retryable")
    func nonRetryable() {
        #expect(!NexNetError.badRequest.isRetryable)
        #expect(!NexNetError.unauthorized.isRetryable)
        #expect(!NexNetError.forbidden.isRetryable)
        #expect(!NexNetError.notFound(url: "").isRetryable)
        #expect(!NexNetError.cancelled.isRetryable)
        #expect(!NexNetError.unprocessableEntity.isRetryable)
        #expect(!NexNetError.decodingFailed(URLError(.unknown), codingPath: "").isRetryable)
        #expect(!NexNetError.encodingFailed(URLError(.unknown)).isRetryable)
    }

    // MARK: - localizedDescription

    @Test("Every case produces a non-empty localizedDescription")
    func allCasesHaveDescriptions() {
        let allCases: [NexNetError] = [
            .invalidURL("bad-url"),
            .noInternetConnection, .timeout, .cancelled,
            .sslError(URLError(.secureConnectionFailed)),
            .badRequest, .unauthorized, .forbidden,
            .notFound(url: "/missing"),
            .unprocessableEntity,
            .tooManyRequests(retryAfter: nil),
            .tooManyRequests(retryAfter: "60"),
            .internalServerError, .badGateway,
            .serviceUnavailable(retryAfter: nil),
            .serviceUnavailable(retryAfter: "30"),
            .gatewayTimeout,
            .httpError(statusCode: 418, data: nil),
            .emptyResponse,
            .decodingFailed(URLError(.unknown), codingPath: "user.name"),
            .encodingFailed(URLError(.unknown)),
            .unknown(URLError(.unknown))
        ]
        for error in allCases {
            #expect(!error.localizedDescription.isEmpty,
                    "Missing description for \(error)")
        }
    }

    @Test("retryAfter value appears in tooManyRequests description")
    func retryAfterInTooManyRequests() {
        let error = NexNetError.tooManyRequests(retryAfter: "120")
        #expect(error.localizedDescription.contains("120"))
    }

    @Test("retryAfter value appears in serviceUnavailable description")
    func retryAfterInServiceUnavailable() {
        let error = NexNetError.serviceUnavailable(retryAfter: "45")
        #expect(error.localizedDescription.contains("45"))
    }

    @Test("codingPath appears in decodingFailed description")
    func codingPathInDecodingFailed() {
        let error = NexNetError.decodingFailed(URLError(.unknown), codingPath: "user.address.zip")
        #expect(error.localizedDescription.contains("user.address.zip"))
    }

    @Test("Empty codingPath omits path segment from description")
    func emptycodingPathDescription() {
        let error = NexNetError.decodingFailed(URLError(.unknown), codingPath: "")
        #expect(!error.localizedDescription.contains("path"))
    }

    // MARK: - NSError bridging (CustomNSError)

    @Test("NSError domain is com.nexnet.error")
    func nsErrorDomain() {
        let cases: [NexNetError] = [.unauthorized, .timeout, .decodingFailed(URLError(.unknown), codingPath: "")]
        for error in cases {
            #expect((error as NSError).domain == "com.nexnet.error",
                    "Wrong domain for \(error)")
        }
    }

    @Test("HTTP errors use their status code as NSError code")
    func nsErrorCodeForHTTPErrors() {
        #expect((NexNetError.badRequest        as NSError).code == 400)
        #expect((NexNetError.unauthorized      as NSError).code == 401)
        #expect((NexNetError.forbidden         as NSError).code == 403)
        #expect((NexNetError.notFound(url: "") as NSError).code == 404)
        #expect((NexNetError.unprocessableEntity as NSError).code == 422)
        #expect((NexNetError.tooManyRequests(retryAfter: nil) as NSError).code == 429)
        #expect((NexNetError.internalServerError as NSError).code == 500)
        #expect((NexNetError.badGateway        as NSError).code == 502)
        #expect((NexNetError.serviceUnavailable(retryAfter: nil) as NSError).code == 503)
        #expect((NexNetError.gatewayTimeout    as NSError).code == 504)
    }

    @Test("Non-HTTP errors use negative NSError codes in the -2000 range")
    func nsErrorCodeForNonHTTPErrors() {
        #expect((NexNetError.invalidURL("")           as NSError).code == -2001)
        #expect((NexNetError.noInternetConnection      as NSError).code == -2002)
        #expect((NexNetError.timeout                   as NSError).code == -2003)
        #expect((NexNetError.cancelled                 as NSError).code == -2004)
        #expect((NexNetError.emptyResponse             as NSError).code == -2006)
        #expect((NexNetError.decodingFailed(URLError(.unknown), codingPath: "") as NSError).code == -2007)
        #expect((NexNetError.encodingFailed(URLError(.unknown)) as NSError).code == -2008)
    }

    @Test("NSError userInfo contains NSLocalizedDescriptionKey")
    func nsErrorUserInfoDescription() {
        let nsError = NexNetError.forbidden as NSError
        #expect(nsError.userInfo[NSLocalizedDescriptionKey] as? String != nil)
    }

    @Test("NSError userInfo contains NSLocalizedRecoverySuggestionErrorKey where applicable")
    func nsErrorUserInfoRecoverySuggestion() {
        // unauthorized has a recovery suggestion ("Sign in again…")
        let nsError = NexNetError.unauthorized as NSError
        #expect(nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String != nil)
    }

    // MARK: - NexNetError.from(_:)

    @Test("NSURLErrorTimedOut maps to .timeout")
    func fromTimedOut() {
        let result = NexNetError.from(URLError(.timedOut))
        guard case .timeout = result else {
            Issue.record("Expected .timeout, got \(result)"); return
        }
    }

    @Test("NSURLErrorNotConnectedToInternet maps to .noInternetConnection")
    func fromNotConnected() {
        let result = NexNetError.from(URLError(.notConnectedToInternet))
        guard case .noInternetConnection = result else {
            Issue.record("Expected .noInternetConnection, got \(result)"); return
        }
    }

    @Test("NSURLErrorNetworkConnectionLost maps to .noInternetConnection")
    func fromConnectionLost() {
        let result = NexNetError.from(URLError(.networkConnectionLost))
        guard case .noInternetConnection = result else {
            Issue.record("Expected .noInternetConnection, got \(result)"); return
        }
    }

    @Test("NSURLErrorCancelled maps to .cancelled")
    func fromCancelled() {
        let result = NexNetError.from(URLError(.cancelled))
        guard case .cancelled = result else {
            Issue.record("Expected .cancelled, got \(result)"); return
        }
    }

    @Test("NSURLErrorSecureConnectionFailed maps to .sslError")
    func fromSSL() {
        let result = NexNetError.from(URLError(.secureConnectionFailed))
        guard case .sslError = result else {
            Issue.record("Expected .sslError, got \(result)"); return
        }
    }

    @Test("An existing NexNetError is returned unchanged (no double-wrapping)")
    func fromPassthrough() {
        let original = NexNetError.forbidden
        let result   = NexNetError.from(original)
        guard case .forbidden = result else {
            Issue.record("Expected .forbidden passthrough, got \(result)"); return
        }
    }

    @Test("Unrecognised URLError wraps in .unknown")
    func fromUnknown() {
        let result = NexNetError.from(URLError(.badURL))
        guard case .unknown = result else {
            Issue.record("Expected .unknown, got \(result)"); return
        }
    }
}
