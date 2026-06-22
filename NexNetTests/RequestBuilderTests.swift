//
//  RequestBuilderTests.swift
//  NexNetTests
//

import Testing
import Foundation
@testable import NexNet

@Suite("RequestBuilder")
struct RequestBuilderTests {

    private let base = URL(string: "https://api.example.com/users")!

    // MARK: - URL

    @Test("URL passes through unchanged when no query parameters are set")
    func urlPassthrough() throws {
        let urlRequest = try RequestBuilder().build(from: NetworkRequest(url: base))
        #expect(urlRequest.url == base)
    }

    @Test("Query parameters are appended to the URL in alphabetical key order")
    func queryParametersAppended() throws {
        let req = NetworkRequest(url: base, queryParameters: ["z": "last", "a": "first", "m": "mid"])
        let urlRequest = try RequestBuilder().build(from: req)
        let items = URLComponents(url: urlRequest.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.count == 3)
        #expect(items[0] == URLQueryItem(name: "a", value: "first"))
        #expect(items[1] == URLQueryItem(name: "m", value: "mid"))
        #expect(items[2] == URLQueryItem(name: "z", value: "last"))
    }

    @Test("Existing query parameters in the URL are preserved when new ones are added")
    func queryParametersMerged() throws {
        let url = URL(string: "https://api.example.com/users?page=1")!
        let req = NetworkRequest(url: url, queryParameters: ["limit": "20"])
        let urlRequest = try RequestBuilder().build(from: req)
        let items = URLComponents(url: urlRequest.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "page", value: "1")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "20")))
    }

    // MARK: - HTTP Method

    @Test("HTTP method is set correctly for GET")
    func methodGET() throws {
        let req = NetworkRequest(url: base, method: .get)
        #expect(try RequestBuilder().build(from: req).httpMethod == "GET")
    }

    @Test("HTTP method is set correctly for POST")
    func methodPOST() throws {
        let req = NetworkRequest(url: base, method: .post, body: .json(Data()))
        #expect(try RequestBuilder().build(from: req).httpMethod == "POST")
    }

    @Test("HTTP method is set correctly for DELETE")
    func methodDELETE() throws {
        let req = NetworkRequest(url: base, method: .delete)
        #expect(try RequestBuilder().build(from: req).httpMethod == "DELETE")
    }

    // MARK: - Headers

    @Test("Default headers from RequestBuilder are applied to every request")
    func defaultHeadersApplied() throws {
        let builder = RequestBuilder(defaultHeaders: ["X-Default": "yes", "Accept": "application/json"])
        let urlRequest = try builder.build(from: NetworkRequest(url: base))
        #expect(urlRequest.value(forHTTPHeaderField: "X-Default") == "yes")
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Per-request headers override default headers on key collision")
    func perRequestHeadersOverrideDefaults() throws {
        let builder = RequestBuilder(defaultHeaders: ["X-Token": "default-token"])
        let req = NetworkRequest(url: base, headers: ["X-Token": "per-request-token"])
        let urlRequest = try builder.build(from: req)
        #expect(urlRequest.value(forHTTPHeaderField: "X-Token") == "per-request-token")
    }

    @Test("Default headers and per-request headers are both present when keys differ")
    func headersAreMerged() throws {
        let builder = RequestBuilder(defaultHeaders: ["Accept": "application/json"])
        let req = NetworkRequest(url: base, headers: ["X-Custom": "value"])
        let urlRequest = try builder.build(from: req)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(urlRequest.value(forHTTPHeaderField: "X-Custom") == "value")
    }

    // MARK: - Body: JSON

    @Test("JSON body is attached as httpBody")
    func jsonBodyData() throws {
        let data = try JSONEncoder().encode(["key": "value"])
        let req = NetworkRequest(url: base, method: .post, body: .json(data))
        let urlRequest = try RequestBuilder().build(from: req)
        #expect(urlRequest.httpBody == data)
    }

    @Test("JSON body sets Content-Type: application/json")
    func jsonBodyContentType() throws {
        let req = NetworkRequest(url: base, method: .post, body: .json(Data()))
        let urlRequest = try RequestBuilder().build(from: req)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true)
    }

    @Test("JSON body does not overwrite an explicit Content-Type header")
    func jsonBodyPreservesExplicitContentType() throws {
        let req = NetworkRequest(
            url: base, method: .post,
            headers: ["Content-Type": "application/json; charset=utf-16"],
            body: .json(Data())
        )
        let urlRequest = try RequestBuilder().build(from: req)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-16")
    }

    // MARK: - Body: FormURLEncoded

    @Test("FormURLEncoded body sets application/x-www-form-urlencoded Content-Type")
    func formURLEncodedContentType() throws {
        let req = NetworkRequest(url: base, method: .post,
                                 body: .formURLEncoded(["user": "alice"]))
        let urlRequest = try RequestBuilder().build(from: req)
        let ct = urlRequest.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(ct.contains("application/x-www-form-urlencoded"))
    }

    @Test("FormURLEncoded body encodes key-value pairs")
    func formURLEncodedBody() throws {
        let req = NetworkRequest(url: base, method: .post,
                                 body: .formURLEncoded(["username": "alice", "score": "99"]))
        let urlRequest = try RequestBuilder().build(from: req)
        let body = String(data: urlRequest.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("username=alice"))
        #expect(body.contains("score=99"))
    }

    // MARK: - Body: Raw

    @Test("Raw body sets supplied bytes and Content-Type")
    func rawBody() throws {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let req = NetworkRequest(url: base, method: .put,
                                 body: .raw(data, contentType: "application/octet-stream"))
        let urlRequest = try RequestBuilder().build(from: req)
        #expect(urlRequest.httpBody == data)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
    }

    // MARK: - Body: Empty

    @Test("Empty body produces no httpBody and no Content-Type header")
    func emptyBody() throws {
        let req = NetworkRequest(url: base, method: .get, body: .empty)
        let urlRequest = try RequestBuilder().build(from: req)
        let isEmpty = urlRequest.httpBody == nil || urlRequest.httpBody?.isEmpty == true
        #expect(isEmpty)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    // MARK: - Body: Multipart

    @Test("Multipart body includes boundary in Content-Type")
    func multipartContentType() throws {
        let part = MultipartFormData.Part(
            name: "file", data: Data("hello".utf8),
            filename: "hello.txt", mimeType: "text/plain"
        )
        let form = MultipartFormData(parts: [part], boundary: "test-boundary-123")
        let req = NetworkRequest(url: base, method: .post, body: .multipart(form))
        let urlRequest = try RequestBuilder().build(from: req)
        let ct = urlRequest.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(ct.contains("multipart/form-data"))
        #expect(ct.contains("test-boundary-123"))
    }

    @Test("Multipart body contains boundary markers and part data")
    func multipartBodyContent() throws {
        let part = MultipartFormData.Part(
            name: "avatar", data: Data("PNG-bytes".utf8),
            filename: "avatar.png", mimeType: "image/png"
        )
        let form = MultipartFormData(parts: [part], boundary: "my-boundary")
        let req = NetworkRequest(url: base, method: .post, body: .multipart(form))
        let urlRequest = try RequestBuilder().build(from: req)
        let body = String(data: urlRequest.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("--my-boundary"))
        #expect(body.contains("--my-boundary--"))
        #expect(body.contains("avatar.png"))
        #expect(body.contains("image/png"))
    }

    // MARK: - Timeout & Cache Policy

    @Test("Timeout interval is forwarded to URLRequest")
    func timeoutForwarded() throws {
        let req = NetworkRequest(url: base, timeoutInterval: 90)
        let urlRequest = try RequestBuilder().build(from: req)
        #expect(urlRequest.timeoutInterval == 90)
    }

    @Test("Cache policy is forwarded to URLRequest")
    func cachePolicyForwarded() throws {
        let req = NetworkRequest(url: base, cachePolicy: .reloadIgnoringLocalCacheData)
        let urlRequest = try RequestBuilder().build(from: req)
        #expect(urlRequest.cachePolicy == .reloadIgnoringLocalCacheData)
    }
}
