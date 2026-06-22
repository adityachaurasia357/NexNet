//
//  NetworkRequest.swift
//  NexNet
//

import Foundation

public enum HTTPMethod: String, Sendable {
    case get     = "GET"
    case post    = "POST"
    case put     = "PUT"
    case patch   = "PATCH"
    case delete  = "DELETE"
    case head    = "HEAD"
    case options = "OPTIONS"
}

public enum RequestBody: Sendable {
    case json(Data)
    case raw(Data, contentType: String)
    case formURLEncoded([String: String])
    case multipart(MultipartFormData)
    case empty

    /// Encodes an `Encodable` value to JSON and wraps it as a `.json` body.
    public static func json<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> RequestBody {
        .json(try encoder.encode(value))
    }
}

public struct MultipartFormData: Sendable {
    public struct Part: Sendable {
        public let name: String
        public let data: Data
        public let filename: String?
        public let mimeType: String?

        public init(name: String, data: Data, filename: String? = nil, mimeType: String? = nil) {
            self.name = name
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
        }
    }

    public let parts: [Part]
    public let boundary: String

    public init(parts: [Part], boundary: String = UUID().uuidString) {
        self.parts = parts
        self.boundary = boundary
    }
}

public struct RetryPolicy: Sendable {
    public enum BackoffStrategy: Sendable {
        case constant(TimeInterval)
        case linear(base: TimeInterval)
        case exponential(base: TimeInterval, multiplier: Double)
    }

    public let maxAttempts: Int
    public let backoffStrategy: BackoffStrategy

    public static let `default` = RetryPolicy(
        maxAttempts: 3,
        backoffStrategy: .exponential(base: 1.0, multiplier: 2.0)
    )
    public static let none = RetryPolicy(maxAttempts: 0, backoffStrategy: .constant(0))

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

public struct NetworkRequest: Sendable {
    public let url: URL
    public let method: HTTPMethod
    public let headers: [String: String]
    public let body: RequestBody
    public let queryParameters: [String: String]
    public let timeoutInterval: TimeInterval
    public let retryPolicy: RetryPolicy
    public let cachePolicy: URLRequest.CachePolicy

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
