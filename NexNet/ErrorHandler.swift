//
//  ErrorHandler.swift
//  NexNet
//

import Foundation

/// A typed error thrown by every NexNet operation.
///
/// Every case maps to a distinct failure mode — a specific HTTP status code, a network
/// condition, or a local encode/decode failure. Use `switch` to handle each case with
/// precision, or check `isRetryable`, `statusCode`, and `localizedDescription` for
/// generic handling.
public enum NexNetError: Error, LocalizedError, @unchecked Sendable {

    // MARK: URL

    /// The URL string could not be parsed into a valid `URL`.
    case invalidURL(String)

    // MARK: Network conditions

    /// The device has no active internet connection.
    case noInternetConnection
    /// The request exceeded the configured timeout interval.
    case timeout
    /// The request was cancelled (e.g. via `Task.cancel()`).
    case cancelled
    /// An SSL/TLS certificate or secure-connection error occurred.
    case sslError(any Error)

    // MARK: Client errors (4xx)

    /// 400 — The server could not understand the request due to malformed syntax.
    case badRequest
    /// 401 — Authentication credentials are missing or invalid.
    case unauthorized
    /// 403 — The server understood the request but refuses to authorise it.
    case forbidden
    /// 404 — The requested resource does not exist at the given URL.
    case notFound(url: String)
    /// 422 — The request was well-formed but contains semantic validation errors.
    case unprocessableEntity
    /// 429 — The client has sent too many requests. `retryAfter` is the `Retry-After` header value when present.
    case tooManyRequests(retryAfter: String?)

    // MARK: Server errors (5xx)

    /// 500 — The server encountered an unexpected internal error.
    case internalServerError
    /// 502 — The server, acting as a gateway, received an invalid upstream response.
    case badGateway
    /// 503 — The server is temporarily unavailable. `retryAfter` is the `Retry-After` header value when present.
    case serviceUnavailable(retryAfter: String?)
    /// 504 — The upstream server failed to respond within the allowed time.
    case gatewayTimeout

    // MARK: Other HTTP

    /// An HTTP error whose status code is not individually mapped above.
    case httpError(statusCode: Int, data: Data?)

    // MARK: Body

    /// The server returned an empty body when a decodable value was expected.
    case emptyResponse
    /// JSON decoding failed. `codingPath` indicates which key or index caused the error.
    case decodingFailed(any Error, codingPath: String)
    /// Serialising the request body to JSON failed.
    case encodingFailed(any Error)

    // MARK: Catch-all

    /// An unexpected error not covered by the cases above.
    case unknown(any Error)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {

        case .invalidURL(let url):
            return "'\(url)' is not a valid URL. Check for typos or missing percent-encoding."

        case .noInternetConnection:
            return "You appear to be offline. Check your network connection and try again."

        case .timeout:
            return "The request timed out. The server may be slow or temporarily unreachable."

        case .cancelled:
            return "The request was cancelled."

        case .sslError(let error):
            return "A secure connection could not be established: \(error.localizedDescription)"

        case .badRequest:
            return "The server rejected the request (400 Bad Request). Verify the request parameters."

        case .unauthorized:
            return "Authentication is required or your credentials are invalid (401 Unauthorized)."

        case .forbidden:
            return "Access to this resource is denied (403 Forbidden). You lack the necessary permissions."

        case .notFound(let url):
            return "No resource was found at '\(url)' (404 Not Found)."

        case .unprocessableEntity:
            return "The request body failed server-side validation (422 Unprocessable Entity)."

        case .tooManyRequests(let retryAfter):
            if let retryAfter {
                return "Rate limit exceeded (429 Too Many Requests). Retry after \(retryAfter) second(s)."
            }
            return "Rate limit exceeded (429 Too Many Requests). Reduce request frequency and try again."

        case .internalServerError:
            return "The server encountered an internal error (500 Internal Server Error). Try again later."

        case .badGateway:
            return "The server received an invalid response from an upstream server (502 Bad Gateway)."

        case .serviceUnavailable(let retryAfter):
            if let retryAfter {
                return "Service temporarily unavailable (503). Retry after \(retryAfter) second(s)."
            }
            return "The service is temporarily unavailable (503 Service Unavailable). Try again later."

        case .gatewayTimeout:
            return "The upstream server did not respond in time (504 Gateway Timeout)."

        case .httpError(let code, _):
            return "The request failed with HTTP status code \(code)."

        case .emptyResponse:
            return "The server returned an empty response body when content was expected."

        case .decodingFailed(let error, let path):
            if path.isEmpty {
                return "Failed to decode the response: \(error.localizedDescription)"
            }
            return "Failed to decode the response at path '\(path)': \(error.localizedDescription)"

        case .encodingFailed(let error):
            return "Failed to encode the request body: \(error.localizedDescription)"

        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noInternetConnection:   return "Enable Wi-Fi or mobile data and retry."
        case .unauthorized:           return "Sign in again or refresh your access token."
        case .forbidden:              return "Contact the resource owner to request access."
        case .tooManyRequests, .serviceUnavailable:
                                      return "Wait before retrying, or implement exponential back-off."
        case .sslError:               return "Verify the server certificate or check your network proxy settings."
        case .decodingFailed:         return "Ensure the response schema matches the expected type."
        default:                      return nil
        }
    }

    // MARK: - Helpers

    /// `true` for errors where the same request may succeed if retried.
    public var isRetryable: Bool {
        switch self {
        case .timeout, .noInternetConnection,
             .internalServerError, .badGateway, .gatewayTimeout,
             .tooManyRequests, .serviceUnavailable:
            return true
        default:
            return false
        }
    }

    /// The HTTP status code associated with this error, if any.
    public var statusCode: Int? {
        switch self {
        case .badRequest:            return 400
        case .unauthorized:          return 401
        case .forbidden:             return 403
        case .notFound:              return 404
        case .unprocessableEntity:   return 422
        case .tooManyRequests:       return 429
        case .internalServerError:   return 500
        case .badGateway:            return 502
        case .serviceUnavailable:    return 503
        case .gatewayTimeout:        return 504
        case .httpError(let code, _): return code
        default:                     return nil
        }
    }

    // MARK: - Factory

    /// Maps a raw `Error` (typically from `URLSession`) to a typed `NexNetError`.
    static func from(_ error: any Error) -> NexNetError {
        if let nexNetError = error as? NexNetError { return nexNetError }

        let nsError = error as NSError

        switch nsError.code {
        case NSURLErrorTimedOut:
            return .timeout

        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed:
            return .noInternetConnection

        case NSURLErrorCancelled:
            return .cancelled

        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .sslError(error)

        default:
            return .unknown(error)
        }
    }
}

// MARK: - DecodingError path extraction

extension DecodingError {
    /// Dot-separated coding path to the key or index that caused the failure.
    var codingPathString: String {
        let path: [CodingKey]
        switch self {
        case .keyNotFound(let key, let ctx):
            path = ctx.codingPath + [key]
        case .typeMismatch(_, let ctx),
             .valueNotFound(_, let ctx),
             .dataCorrupted(let ctx):
            path = ctx.codingPath
        @unknown default:
            return ""
        }
        return path.map { key in
            key.intValue.map { "[\($0)]" } ?? key.stringValue
        }.joined(separator: ".")
    }
}
