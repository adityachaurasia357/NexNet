//
//  ResponseHandler.swift
//  NexNet
//

import Foundation

/// Validates raw HTTP responses and decodes their bodies.
///
/// Implement this protocol to substitute the default `ResponseHandler` with a custom
/// implementation (e.g. for testing or non-standard error mapping).
public protocol ResponseHandlerProtocol: Sendable {
    /// Validates that `response` is a successful HTTP response.
    ///
    /// - Parameters:
    ///   - response: The `URLResponse` returned by `URLSession`.
    ///   - data: The raw response bytes (used to populate error payloads).
    /// - Returns: The cast `HTTPURLResponse` when the status code is 2xx.
    /// - Throws: A `NexNetError` case that matches the HTTP status code.
    func validate(_ response: URLResponse, data: Data) throws -> HTTPURLResponse

    /// Decodes `data` into the requested `Decodable` type.
    ///
    /// - Parameters:
    ///   - type: The target `Decodable` type.
    ///   - data: Raw response bytes.
    ///   - decoder: The `JSONDecoder` to use.
    /// - Returns: An instance of `T`.
    /// - Throws: `NexNetError.emptyResponse` or `NexNetError.decodingFailed` on failure.
    func decode<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder) throws -> T
}

/// Validates HTTP status codes and decodes response bodies.
public struct ResponseHandler: ResponseHandlerProtocol {
    public init() {}

    // MARK: - Decoder Factory

    /// Creates the standard NexNet `JSONDecoder`.
    ///
    /// Configured with:
    /// - `.convertFromSnakeCase` — maps `user_name` → `userName` automatically.
    /// - Custom ISO 8601 date strategy — accepts both plain (`2024-01-15T10:30:00Z`)
    ///   and fractional-second (`2024-01-15T10:30:00.123Z`) variants, covering the
    ///   majority of REST APIs in production.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(iso8601DateDecoder)
        return decoder
    }

    // MARK: - Validation

    /// Maps each HTTP status code to its typed `NexNetError` case.
    ///
    /// 2xx → returns the response unchanged.
    /// 4xx/5xx → throws the named error case, extracting `Retry-After` for 429 and 503.
    public func validate(_ response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw NexNetError.httpError(statusCode: -1, data: data)
        }

        switch http.statusCode {
        case 200..<300:
            return http
        case 400:
            throw NexNetError.badRequest
        case 401:
            throw NexNetError.unauthorized
        case 403:
            throw NexNetError.forbidden
        case 404:
            throw NexNetError.notFound(url: http.url?.absoluteString ?? "unknown")
        case 422:
            throw NexNetError.unprocessableEntity
        case 429:
            throw NexNetError.tooManyRequests(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        case 500:
            throw NexNetError.internalServerError
        case 502:
            throw NexNetError.badGateway
        case 503:
            throw NexNetError.serviceUnavailable(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        case 504:
            throw NexNetError.gatewayTimeout
        default:
            throw NexNetError.httpError(statusCode: http.statusCode, data: data)
        }
    }

    // MARK: - Decoding

    /// Decodes `data` into `T` using the supplied `decoder`.
    ///
    /// **Empty body handling:**
    /// When `data` is empty (e.g. 204 No Content or a DELETE response), the method
    /// checks whether the caller declared `T == EmptyResponse`. If so it returns
    /// `EmptyResponse()` directly — no JSON parsing attempted. If `T` is any other
    /// type, `NexNetError.emptyResponse` is thrown so the caller is alerted.
    ///
    /// **Decoding failures:**
    /// Any `DecodingError` is re-thrown as `NexNetError.decodingFailed(_:codingPath:)`
    /// with a human-readable dot-path (e.g. `"user.address.zipCode"`) pinpointing
    /// the offending key or index.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder) throws -> T {
        if data.isEmpty {
            // Graceful empty-body path for 204 / DELETE / void-like responses.
            if let empty = EmptyResponse() as? T {
                return empty
            }
            throw NexNetError.emptyResponse
        }

        do {
            return try decoder.decode(type, from: data)
        } catch let decodingError as DecodingError {
            throw NexNetError.decodingFailed(decodingError, codingPath: decodingError.codingPathString)
        } catch {
            throw NexNetError.decodingFailed(error, codingPath: "")
        }
    }
}

// MARK: - ISO 8601 date decoding

/// Accepts both plain and fractional-second ISO 8601 strings.
///
/// Plain:        `2024-01-15T10:30:00Z`
/// Fractional:   `2024-01-15T10:30:00.123Z`
/// Offset:       `2024-01-15T10:30:00+05:30`
private func iso8601DateDecoder(_ decoder: Decoder) throws -> Date {
    // Formatters are created once (at module load time) and reused across calls.
    // ISO8601DateFormatter is safe for concurrent reads after initial configuration.
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)

    if let date = ISO8601Formatters.fractional.date(from: string)
        ?? ISO8601Formatters.plain.date(from: string) {
        return date
    }

    throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected an ISO 8601 date string, but got '\(string)'."
    )
}

private enum ISO8601Formatters {
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
