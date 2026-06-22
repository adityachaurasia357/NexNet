//
//  NetworkResponse.swift
//  NexNet
//

import Foundation

/// A decoded response paired with full HTTP metadata.
///
/// Returned by `NetworkManager.request(_:as:decoder:)`. Use `value` for the decoded
/// payload; `statusCode`, `headers`, `rawData`, and `duration` for diagnostics.
public struct NetworkResponse<T: Decodable & Sendable>: Sendable {
    /// The decoded response body.
    public let value: T
    /// The HTTP status code (e.g. `200`, `201`).
    public let statusCode: Int
    /// Response headers keyed by lowercase field name.
    public let headers: [String: String]
    /// The raw response bytes before decoding.
    public let rawData: Data
    /// Total elapsed time from request dispatch to response receipt, including all retry attempts.
    public let duration: TimeInterval

    /// `true` when `statusCode` is in the 2xx range.
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
///
/// Returned by `NetworkManager.requestRaw(_:)`. Use this when you need the raw bytes
/// (e.g. image downloads, streaming, or custom decoding pipelines).
public struct RawNetworkResponse: Sendable {
    /// The HTTP status code.
    public let statusCode: Int
    /// Response headers keyed by lowercase field name.
    public let headers: [String: String]
    /// Raw response bytes.
    public let data: Data
    /// Total elapsed time from request dispatch to response receipt, including all retry attempts.
    public let duration: TimeInterval

    /// `true` when `statusCode` is in the 2xx range.
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
