//
//  NetworkRequest.swift
//  NexNet
//
//  Created by Aditya Chaurasia on 22/06/2026.
//

import Foundation

/// The HTTP verb used for a request.
public enum HTTPMethod: String, Sendable {
    /// Retrieve a resource without modifying server state.
    case get     = "GET"
    /// Submit data to create or trigger a resource.
    case post    = "POST"
    /// Replace an existing resource entirely.
    case put     = "PUT"
    /// Partially update an existing resource.
    case patch   = "PATCH"
    /// Remove a resource.
    case delete  = "DELETE"
    /// Retrieve only the response headers, no body.
    case head    = "HEAD"
    /// Query the supported HTTP methods for a resource.
    case options = "OPTIONS"
}

/// The payload format for an HTTP request body.
///
/// NexNet automatically sets `Content-Type` based on the case you choose:
/// - `.json` → `application/json; charset=utf-8`
/// - `.raw` → the `contentType` you supply
/// - `.formURLEncoded` → `application/x-www-form-urlencoded; charset=utf-8`
/// - `.multipart` → `multipart/form-data; boundary=…`
/// - `.empty` → no body, no `Content-Type` header
public enum RequestBody: Sendable {
    /// Pre-encoded JSON bytes. Use the `json(_:encoder:)` factory when you have an `Encodable` value.
    case json(Data)
    /// Arbitrary binary payload with an explicit MIME type.
    case raw(Data, contentType: String)
    /// URL-encoded form fields (`key=value&key2=value2`).
    case formURLEncoded([String: String])
    /// Multipart form data; typically used for file uploads.
    case multipart(MultipartFormData)
    /// No body. Used for GET, DELETE, and other bodyless requests.
    case empty

    /// Encodes an `Encodable` value to JSON and wraps it as a `.json` body.
    public static func json<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> RequestBody {
        .json(try encoder.encode(value))
    }
}

/// A collection of named parts used to build a `multipart/form-data` request body.
public struct MultipartFormData: Sendable {
    /// A single field or file within a multipart body.
    public struct Part: Sendable {
        /// The form field name (`Content-Disposition: form-data; name="…"`).
        public let name: String
        /// The raw bytes for this part.
        public let data: Data
        /// Optional filename included in the `Content-Disposition` header.
        public let filename: String?
        /// Optional MIME type included as a `Content-Type` header for this part.
        public let mimeType: String?

        /// Creates a multipart part.
        ///
        /// - Parameters:
        ///   - name: Form field name.
        ///   - data: Raw bytes of the field value or file content.
        ///   - filename: Filename to include in `Content-Disposition` (optional).
        ///   - mimeType: MIME type for this part's `Content-Type` header (optional).
        public init(name: String, data: Data, filename: String? = nil, mimeType: String? = nil) {
            self.name = name
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
        }
    }

    /// The ordered parts that make up this multipart body.
    public let parts: [Part]
    /// The boundary string used to delimit parts. Defaults to a random UUID string.
    public let boundary: String

    /// Creates a `MultipartFormData` value.
    ///
    /// - Parameters:
    ///   - parts: The ordered list of form parts.
    ///   - boundary: Boundary delimiter. Defaults to a UUID string.
    public init(parts: [Part], boundary: String = UUID().uuidString) {
        self.parts = parts
        self.boundary = boundary
    }
}

/// Controls how and how many times a failed request is retried.
///
/// Only errors where `NexNetError.isRetryable == true` trigger a retry.
/// Attach a policy to `NetworkRequest.retryPolicy`; the default is `.none`.
public struct RetryPolicy: Sendable {
    /// The algorithm used to compute the delay between retry attempts.
    public enum BackoffStrategy: Sendable {
        /// Fixed delay between every attempt.
        case constant(TimeInterval)
        /// Delay grows linearly: `base × attemptNumber`.
        case linear(base: TimeInterval)
        /// Delay grows exponentially: `base × multiplierⁿ` (recommended for production).
        case exponential(base: TimeInterval, multiplier: Double)
    }

    /// Maximum number of retry attempts after the initial failure.
    public let maxAttempts: Int
    /// The algorithm used to space out retry attempts.
    public let backoffStrategy: BackoffStrategy

    /// Three attempts with exponential back-off starting at 1 s × 2.0.
    public static let `default` = RetryPolicy(
        maxAttempts: 3,
        backoffStrategy: .exponential(base: 1.0, multiplier: 2.0)
    )
    /// No retries. This is the default for all `NetworkRequest` instances.
    public static let none = RetryPolicy(maxAttempts: 0, backoffStrategy: .constant(0))

    /// Creates a `RetryPolicy`.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retries after the first failure.
    ///   - backoffStrategy: Delay algorithm between attempts. Defaults to exponential `1 s × 2.0`.
    public init(maxAttempts: Int, backoffStrategy: BackoffStrategy = .exponential(base: 1.0, multiplier: 2.0)) {
        self.maxAttempts = maxAttempts
        self.backoffStrategy = backoffStrategy
    }

    func delay(for attempt: Int) -> TimeInterval {
        switch backoffStrategy {
        case .constant(let interval):
            return interval
        case .linear(let base):
            return base * Double(attempt)
        case .exponential(let base, let multiplier):
            return base * pow(multiplier, Double(attempt - 1))
        }
    }
}

/// A value-type description of an HTTP request, including URL, method, headers, body, and policy.
///
/// Pass a `NetworkRequest` to `NetworkManager.request(_:as:decoder:)` or
/// `NetworkManager.requestRaw(_:)` when you need control over retry policy, cache policy,
/// or query parameters. Use `NetworkManager.fetch(responseType:url:headers:body:method:)`
/// for the simpler, higher-level path.
public struct NetworkRequest: Sendable {
    /// The fully-resolved URL for the request.
    public let url: URL
    /// The HTTP verb (GET, POST, PUT, PATCH, DELETE, …).
    public let method: HTTPMethod
    /// Per-request headers merged on top of the manager's default headers.
    public let headers: [String: String]
    /// The encoded request body. Use `.empty` for bodyless requests.
    public let body: RequestBody
    /// Key-value pairs appended to the URL as a query string.
    public let queryParameters: [String: String]
    /// Request timeout in seconds. Defaults to 30 s; overridden by `NexNetConfig.timeout`
    /// only when this property still carries its default value.
    public let timeoutInterval: TimeInterval
    /// Retry policy applied on retryable failures. Defaults to `.none`.
    public let retryPolicy: RetryPolicy
    /// URLSession cache policy for this request. Defaults to `.useProtocolCachePolicy`.
    public let cachePolicy: URLRequest.CachePolicy

    /// Creates a `NetworkRequest`.
    ///
    /// - Parameters:
    ///   - url: Fully-resolved URL (absolute). Relative paths must be resolved before init.
    ///   - method: HTTP verb. Defaults to `.get`.
    ///   - headers: Per-request headers. Defaults to empty (uses manager defaults only).
    ///   - body: Encoded body. Defaults to `.empty`.
    ///   - queryParameters: Query string key-value pairs. Defaults to empty.
    ///   - timeoutInterval: Timeout in seconds. Defaults to 30 s.
    ///   - retryPolicy: Retry behaviour. Defaults to `.none`.
    ///   - cachePolicy: URLSession cache policy. Defaults to `.useProtocolCachePolicy`.
    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: RequestBody = .empty,
        queryParameters: [String: String] = [:],
        timeoutInterval: TimeInterval = 30.0,
        retryPolicy: RetryPolicy = .none,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.queryParameters = queryParameters
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.cachePolicy = cachePolicy
    }
}
