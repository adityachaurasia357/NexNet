//
//  MockURLProtocol.swift
//  NexNetTests
//
//  Shared test infrastructure. Register MockURLProtocol on an ephemeral
//  URLSessionConfiguration to intercept all requests without hitting the network.
//

import Foundation
@testable import NexNet

// MARK: - MockURLProtocol

/// URLProtocol subclass that short-circuits URLSession requests in tests.
///
/// Set `handler` before each test and reset it to `nil` afterwards to
/// prevent state leaking between tests when the suite runs serially.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    /// Invoked for every request. Return the desired `(HTTPURLResponse, Data)` pair,
    /// or throw to simulate a transport-level error (e.g. `URLError(.timedOut)`).
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        // URLSession delivers POST/PUT/PATCH bodies as httpBodyStream inside URLProtocol,
        // not httpBody. Materialize the stream so handlers can read request.httpBody directly.
        var normalizedRequest = request
        if normalizedRequest.httpBody == nil, let stream = normalizedRequest.httpBodyStream {
            var data = Data()
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n > 0 { data.append(&buffer, count: n) }
            }
            stream.close()
            normalizedRequest.httpBody = data
        }
        do {
            let (response, data) = try handler(normalizedRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Convenience helpers

extension MockURLProtocol {
    /// Builds an `HTTPURLResponse` for the given status code and optional headers.
    static func response(
        for url: URL = URL(string: "https://api.example.com")!,
        statusCode: Int,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url, statusCode: statusCode,
            httpVersion: "HTTP/1.1", headerFields: headers
        )!
    }
}

// MARK: - Manager factory

/// Creates a `NetworkManager` whose `URLSession` is fully intercepted by `MockURLProtocol`.
///
/// Pass `baseURL` to apply `NexNetConfig` immediately; omit it to test URL-resolution failures.
func makeMockManager(
    baseURL: String? = nil,
    defaultHeaders: [String: String] = ["Accept": "application/json"]
) -> NetworkManager {
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [MockURLProtocol.self]

    let manager = NetworkManager(configuration: NetworkManagerConfiguration(
        urlSessionConfiguration: sessionConfig,
        defaultHeaders: defaultHeaders,
        logLevel: .none          // suppress console output in tests
    ))
    if let baseURL {
        manager.configure(with: NexNetConfig(baseURL: baseURL, isLoggingEnabled: false))
    }
    return manager
}

// MARK: - JSON helpers

func jsonData(_ value: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: value)
}
