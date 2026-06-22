//
//  NetworkManagerTests.swift
//  NexNetTests
//
//  Created by Aditya Chaurasia on 22/06/2026.
//
//  Uses MockURLProtocol to intercept URLSession traffic.
//  The suite is serialized because MockURLProtocol.handler is static shared state.
//

import Testing
import Foundation
@testable import NexNet

// MARK: - Shared model

private struct Post: Decodable, Equatable, Sendable {
    let id: Int
    let title: String
}

// MARK: - Suite

@Suite("NetworkManager", .serialized)
struct NetworkManagerTests {

    // Called implicitly before each test — set handler to nil so a forgotten
    // setup in one test cannot affect the next.
    init() { MockURLProtocol.handler = nil }

    // MARK: - URL resolution

    @Test("Absolute URL is sent unchanged, ignoring any configured baseURL")
    func absoluteURLPassthrough() async throws {
        let manager = makeMockManager(baseURL: "https://base.api.com")
        let absoluteURL = "https://other.api.com/posts/1"

        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == absoluteURL)
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 1, "title": "direct"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: absoluteURL,
            headers: nil, body: nil, method: .get
        )
    }

    @Test("Relative path with leading slash is joined to baseURL")
    func relativeURLWithLeadingSlash() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com/v1")

        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.example.com/v1/posts/5")
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 5, "title": "hello"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "/posts/5",
            headers: nil, body: nil, method: .get
        )
    }

    @Test("Relative path without leading slash is joined to baseURL")
    func relativeURLWithoutLeadingSlash() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com/v1")

        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.example.com/v1/posts/6")
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 6, "title": "world"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "posts/6",
            headers: nil, body: nil, method: .get
        )
    }

    @Test("Relative URL without a configured baseURL throws .invalidURL")
    func missingBaseURLThrows() async {
        let manager = makeMockManager()   // no baseURL

        await #expect(throws: NexNetError.self) {
            _ = try await manager.fetch(
                responseType: Post.self, url: "/posts/1",
                headers: nil, body: nil, method: .get
            )
        }
    }

    // MARK: - HTTP method & body

    @Test("GET request sends no body")
    func getHasNoBody() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")

        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil || request.httpBody?.isEmpty == true)
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 1, "title": "ok"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "/posts/1",
            headers: nil, body: nil, method: .get
        )
    }

    @Test("POST request JSON-encodes the Encodable body")
    func postEncodesBody() async throws {
        struct Payload: Encodable { let name: String; let count: Int }
        let manager = makeMockManager(baseURL: "https://api.example.com")

        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            #expect(body?["name"] as? String == "widget")
            #expect(body?["count"] as? Int == 42)
            return (MockURLProtocol.response(for: request.url!, statusCode: 201),
                    jsonData(["id": 2, "title": "new"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "/posts",
            headers: nil, body: Payload(name: "widget", count: 42), method: .post
        )
    }

    // MARK: - Headers

    @Test("Default headers are sent with every request")
    func defaultHeadersSent() async throws {
        let manager = makeMockManager(
            baseURL: "https://api.example.com",
            defaultHeaders: ["Accept": "application/json", "X-Client": "NexNet"]
        )

        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "X-Client") == "NexNet")
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 1, "title": "ok"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "/posts/1",
            headers: nil, body: nil, method: .get
        )
    }

    @Test("Per-request headers are merged with defaults")
    func perRequestHeadersMerged() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")

        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Accept") != nil)
            #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "test-id-123")
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 1, "title": "ok"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "/posts/1",
            headers: ["X-Request-ID": "test-id-123"], body: nil, method: .get
        )
    }

    @Test("Per-request header overrides matching default header")
    func perRequestHeaderOverridesDefault() async throws {
        let manager = makeMockManager(
            baseURL: "https://api.example.com",
            defaultHeaders: ["Accept": "application/json"]
        )

        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.api+json")
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 1, "title": "ok"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "/posts/1",
            headers: ["Accept": "application/vnd.api+json"], body: nil, method: .get
        )
    }

    // MARK: - HTTP error mapping

    @Test("404 response throws .notFound")
    func http404() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        MockURLProtocol.handler = { request in
            (MockURLProtocol.response(for: request.url!, statusCode: 404), Data())
        }

        do {
            _ = try await manager.fetch(responseType: Post.self,
                                        url: "/missing", headers: nil, body: nil, method: .get)
            Issue.record("Expected .notFound to be thrown")
        } catch let e as NexNetError {
            guard case .notFound = e else {
                Issue.record("Expected .notFound, got \(e)"); return
            }
        }
    }

    @Test("401 response throws .unauthorized")
    func http401() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        MockURLProtocol.handler = { _ in (MockURLProtocol.response(statusCode: 401), Data()) }

        do {
            _ = try await manager.fetch(responseType: Post.self,
                                        url: "/secure", headers: nil, body: nil, method: .get)
            Issue.record("Expected .unauthorized to be thrown")
        } catch let e as NexNetError {
            guard case .unauthorized = e else {
                Issue.record("Expected .unauthorized, got \(e)"); return
            }
        }
    }

    @Test("500 response throws .internalServerError")
    func http500() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        MockURLProtocol.handler = { _ in (MockURLProtocol.response(statusCode: 500), Data()) }

        do {
            _ = try await manager.fetch(responseType: Post.self,
                                        url: "/crash", headers: nil, body: nil, method: .get)
            Issue.record("Expected .internalServerError to be thrown")
        } catch let e as NexNetError {
            guard case .internalServerError = e else {
                Issue.record("Expected .internalServerError, got \(e)"); return
            }
        }
    }

    // MARK: - EmptyResponse

    @Test("204 response with EmptyResponse type succeeds without throwing")
    func emptyResponseType() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        MockURLProtocol.handler = { request in (MockURLProtocol.response(for: request.url!, statusCode: 204), Data()) }

        _ = try await manager.fetch(
            responseType: EmptyResponse.self, url: "/posts/1",
            headers: nil, body: nil, method: .delete
        )
    }

    @Test("200 with empty body throws .emptyResponse when a non-empty type is expected")
    func emptyBodyForNonEmptyType() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        MockURLProtocol.handler = { request in (MockURLProtocol.response(for: request.url!, statusCode: 200), Data()) }

        do {
            _ = try await manager.fetch(responseType: Post.self,
                                        url: "/posts/1", headers: nil, body: nil, method: .get)
            Issue.record("Expected .emptyResponse to be thrown")
        } catch let e as NexNetError {
            guard case .emptyResponse = e else {
                Issue.record("Expected .emptyResponse, got \(e)"); return
            }
        }
    }

    // MARK: - Decoding failure

    @Test("Schema mismatch throws .decodingFailed")
    func decodingFailure() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        // 'id' should be Int but the server returns a String
        MockURLProtocol.handler = { request in
            (MockURLProtocol.response(for: request.url!, statusCode: 200),
             Data(#"{"id":"not-a-number","title":"post"}"#.utf8))
        }

        do {
            _ = try await manager.fetch(responseType: Post.self,
                                        url: "/posts/1", headers: nil, body: nil, method: .get)
            Issue.record("Expected .decodingFailed to be thrown")
        } catch let e as NexNetError {
            guard case .decodingFailed = e else {
                Issue.record("Expected .decodingFailed, got \(e)"); return
            }
        }
    }

    // MARK: - configure(with:)

    @Test("configure(with:) updates the base URL for subsequent requests")
    func configureUpdatesBaseURL() async throws {
        let manager = makeMockManager()
        manager.configure(with: NexNetConfig(
            baseURL: "https://reconfigured.api.com",
            isLoggingEnabled: false
        ))

        MockURLProtocol.handler = { request in
            #expect(request.url?.host == "reconfigured.api.com")
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 1, "title": "ok"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "/posts/1",
            headers: nil, body: nil, method: .get
        )
    }

    @Test("configure(with:) merges defaultHeaders — config values win on collision")
    func configureHeaderMerge() async throws {
        let manager = makeMockManager(defaultHeaders: ["Accept": "application/json"])
        manager.configure(with: NexNetConfig(
            baseURL: "https://api.example.com",
            defaultHeaders: ["Accept": "application/vnd.api+json"],
            isLoggingEnabled: false
        ))

        MockURLProtocol.handler = { request in
            // Config header should win
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.api+json")
            return (MockURLProtocol.response(for: request.url!, statusCode: 200),
                    jsonData(["id": 1, "title": "ok"]))
        }

        _ = try await manager.fetch(
            responseType: Post.self, url: "/posts/1",
            headers: nil, body: nil, method: .get
        )
    }

    // MARK: - requestRaw

    @Test("requestRaw returns the raw Data and status code without decoding")
    func requestRawReturnsData() async throws {
        let manager  = makeMockManager()
        let expected = Data(#"{"raw":true}"#.utf8)
        let url      = URL(string: "https://api.example.com/raw")!

        MockURLProtocol.handler = { _ in (MockURLProtocol.response(for: url, statusCode: 200), expected) }

        let response = try await manager.requestRaw(NetworkRequest(url: url))
        #expect(response.data == expected)
        #expect(response.statusCode == 200)
        #expect(response.duration >= 0)
    }

    // MARK: - NetworkResponse metadata

    @Test("request(_:as:) returns NetworkResponse with statusCode, duration, and headers")
    func requestReturnsFullMetadata() async throws {
        let manager = makeMockManager()
        let url     = URL(string: "https://api.example.com/posts/1")!

        MockURLProtocol.handler = { _ in
            (MockURLProtocol.response(for: url, statusCode: 201,
                       headers: ["X-Request-ID": "abc123"]),
             jsonData(["id": 1, "title": "meta"]))
        }

        let response = try await manager.request(NetworkRequest(url: url, method: .post), as: Post.self)
        #expect(response.statusCode == 201)
        #expect(response.duration >= 0)
        #expect(response.isSuccess)
        #expect(response.value == Post(id: 1, title: "meta"))
    }

    // MARK: - Retry policy

    @Test("Retryable 500 error is retried and succeeds on the third attempt")
    func retryOnServerError() async throws {
        let manager = makeMockManager()
        let url     = URL(string: "https://api.example.com/unstable")!
        var callCount = 0

        MockURLProtocol.handler = { _ in
            callCount += 1
            if callCount < 3 {
                return (MockURLProtocol.response(for: url, statusCode: 500), Data())
            }
            return (MockURLProtocol.response(for: url, statusCode: 200), jsonData(["id": 9, "title": "ok"]))
        }

        let req = NetworkRequest(
            url: url, method: .get,
            // Use constant(0) delay so the test doesn't sleep
            retryPolicy: RetryPolicy(maxAttempts: 3, backoffStrategy: .constant(0))
        )
        let response = try await manager.request(req, as: Post.self)
        #expect(response.value.id == 9)
        #expect(callCount == 3)
    }

    @Test("Exhausted retries throw the last error")
    func retriesExhausted() async throws {
        let manager = makeMockManager()
        let url     = URL(string: "https://api.example.com/down")!
        var callCount = 0

        MockURLProtocol.handler = { _ in
            callCount += 1
            return (MockURLProtocol.response(for: url, statusCode: 503), Data())
        }

        let req = NetworkRequest(
            url: url, method: .get,
            retryPolicy: RetryPolicy(maxAttempts: 2, backoffStrategy: .constant(0))
        )
        do {
            _ = try await manager.request(req, as: Post.self)
            Issue.record("Expected an error after retries were exhausted")
        } catch let e as NexNetError {
            guard case .serviceUnavailable = e else {
                Issue.record("Expected .serviceUnavailable, got \(e)"); return
            }
        }
        // 1 initial + 2 retries = 3 total calls
        #expect(callCount == 3)
    }

    @Test("Non-retryable 401 error is not retried")
    func noRetryForClientError() async throws {
        let manager = makeMockManager()
        let url     = URL(string: "https://api.example.com/secure")!
        var callCount = 0

        MockURLProtocol.handler = { _ in
            callCount += 1
            return (MockURLProtocol.response(for: url, statusCode: 401), Data())
        }

        let req = NetworkRequest(
            url: url, method: .get,
            retryPolicy: RetryPolicy(maxAttempts: 3, backoffStrategy: .constant(0))
        )
        await #expect(throws: NexNetError.self) {
            _ = try await manager.request(req, as: Post.self)
        }
        #expect(callCount == 1)
    }

    // MARK: - Completion handler API

    @Test("Completion handler variant delivers success on main queue")
    func completionHandlerSuccess() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        MockURLProtocol.handler = { request in
            (MockURLProtocol.response(for: request.url!, statusCode: 200), jsonData(["id": 3, "title": "cb"]))
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.fetch(responseType: Post.self, url: "/posts/3",
                          callbackQueue: .main) { result in
                switch result {
                case .success(let post):
                    #expect(post.id == 3)
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @Test("Completion handler variant delivers failure")
    func completionHandlerFailure() async throws {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        MockURLProtocol.handler = { _ in (MockURLProtocol.response(statusCode: 403), Data()) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.fetch(responseType: Post.self, url: "/locked",
                          callbackQueue: .main) { result in
                switch result {
                case .success:
                    continuation.resume(throwing: URLError(.unknown))
                case .failure(let error):
                    if case .forbidden = error {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    @Test("NexNetCancellable.cancel() can be called without crashing")
    func cancellableCancel() async {
        let manager = makeMockManager(baseURL: "https://api.example.com")
        MockURLProtocol.handler = { _ in (MockURLProtocol.response(statusCode: 200), jsonData(["id": 1, "title": "x"])) }

        let token = manager.fetch(responseType: Post.self, url: "/posts/1") { _ in }
        token.cancel()   // must not crash or deadlock
    }
}
