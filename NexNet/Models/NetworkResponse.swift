//
//  NetworkResponse.swift
//  NexNet
//

import Foundation

/// A decoded response paired with HTTP metadata.
public struct NetworkResponse<T: Decodable & Sendable>: Sendable {
    public let value: T
    public let statusCode: Int
    public let headers: [String: String]
    public let rawData: Data
    public let duration: TimeInterval

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    init(
        value: T,
        statusCode: Int,
        allHeaderFields: [AnyHashable: Any],
        data: Data,
        duration: TimeInterval
    ) {
        self.value = value
        self.statusCode = statusCode
        self.headers = allHeaderFields.reduce(into: [:]) {
            if let key = $1.key as? String, let val = $1.value as? String { $0[key] = val }
        }
        self.rawData = data
        self.duration = duration
    }
}

/// An undecoded response carrying raw `Data` and HTTP metadata.
public struct RawNetworkResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data
    public let duration: TimeInterval

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    init(
        statusCode: Int,
        allHeaderFields: [AnyHashable: Any],
        data: Data,
        duration: TimeInterval
    ) {
        self.statusCode = statusCode
        self.headers = allHeaderFields.reduce(into: [:]) {
            if let key = $1.key as? String, let val = $1.value as? String { $0[key] = val }
        }
        self.data = data
        self.duration = duration
    }
}

/// Sentinel type for requests that intentionally return no body (204 No Content, DELETE, etc.).
///
/// Pass this as `responseType` when you do not expect a JSON payload:
/// ```swift
/// try await NetworkManager.shared.fetch(
///     responseType: EmptyResponse.self,
///     url: "https://api.example.com/posts/1",
///     headers: nil, body: nil, method: .delete
/// )
/// ```
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
