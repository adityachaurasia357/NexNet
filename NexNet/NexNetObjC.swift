//
//  NexNetObjC.swift
//  NexNet
//
//  Objective-C bridge layer:
//    - NexNetError: CustomNSError   — proper NSError domain/code/userInfo bridging
//    - NexNetClient                 — @objc wrapper class for ObjC and mixed-language targets
//

import Foundation

// MARK: - NexNetError: CustomNSError

extension NexNetError: CustomNSError {

    /// The error domain used for all `NexNetError` instances when bridged to `NSError`.
    ///
    /// In Objective-C: `NexNetErrorDomain` == `@"com.nexnet.error"`
    public static var errorDomain: String { "com.nexnet.error" }

    /// An integer error code suitable for `NSError.code`.
    ///
    /// HTTP errors use their HTTP status code (e.g. `404`, `500`).
    /// Non-HTTP errors use negative values in the `-2000` range:
    ///
    /// | Case | Code |
    /// |------|------|
    /// | `.invalidURL` | -2001 |
    /// | `.noInternetConnection` | -2002 |
    /// | `.timeout` | -2003 |
    /// | `.cancelled` | -2004 |
    /// | `.sslError` | -2005 |
    /// | `.emptyResponse` | -2006 |
    /// | `.decodingFailed` | -2007 |
    /// | `.encodingFailed` | -2008 |
    /// | `.unknown` | -2009 |
    public var errorCode: Int {
        if let code = statusCode { return code }
        switch self {
        case .invalidURL:           return -2001
        case .noInternetConnection: return -2002
        case .timeout:              return -2003
        case .cancelled:            return -2004
        case .sslError:             return -2005
        case .emptyResponse:        return -2006
        case .decodingFailed:       return -2007
        case .encodingFailed:       return -2008
        default:                    return -2009
        }
    }

    /// User-info dictionary for the bridged `NSError`.
    ///
    /// Always includes `NSLocalizedDescriptionKey`.
    /// Includes `NSLocalizedRecoverySuggestionErrorKey` where a recovery suggestion is available.
    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: errorDescription ?? ""]
        if let suggestion = recoverySuggestion {
            info[NSLocalizedRecoverySuggestionErrorKey] = suggestion
        }
        return info
    }
}

// MARK: - NexNetClient

/// Objective-C–compatible wrapper around `NetworkManager`.
///
/// Import NexNet in an Objective-C file with:
/// ```objc
/// @import NexNet;
/// // or
/// #import <NexNet/NexNet-Swift.h>
/// ```
///
/// **Configuration:**
/// ```objc
/// [[NexNetClient shared] configureWithBaseURL:@"https://api.example.com"
///                             defaultHeaders:@{@"Authorization": @"Bearer token"}
///                                    timeout:30
///                             loggingEnabled:YES];
/// ```
///
/// **GET request:**
/// ```objc
/// [[NexNetClient shared] getFromURL:@"/users/1"
///                           headers:nil
///                        completion:^(NSData *data, NSInteger status, NSError *error) {
///     if (error) { NSLog(@"Error: %@", error.localizedDescription); return; }
///     NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
/// }];
/// ```
///
/// **POST request:**
/// ```objc
/// NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"title": @"Hello"} options:0 error:nil];
/// [[NexNetClient shared] postToURL:@"/posts"
///                          headers:nil
///                             body:body
///                       completion:^(NSData *data, NSInteger status, NSError *error) { }];
/// ```
///
/// **Cancellation:**
/// ```objc
/// NexNetCancellable *token = [[NexNetClient shared] getFromURL:@"/feed" headers:nil completion:^(...) { }];
/// [token cancel];
/// ```
@objc public final class NexNetClient: NSObject {

    /// The default shared instance backed by `NetworkManager.shared`.
    @objc public static let shared = NexNetClient()

    private let manager: NetworkManager

    /// Creates a client backed by `NetworkManager.shared`.
    @objc public override init() {
        self.manager = NetworkManager.shared
        super.init()
    }

    /// Creates a client backed by a custom `NetworkManager` instance.
    ///
    /// Useful in tests or when you need isolated sessions.
    /// - Parameter manager: The manager to delegate all requests to.
    public init(manager: NetworkManager) {
        self.manager = manager
        super.init()
    }

    // MARK: - Configuration

    /// Configures the underlying `NetworkManager`.
    ///
    /// Call once at app startup (e.g. in `application:didFinishLaunchingWithOptions:`).
    /// Subsequent calls replace the previous configuration atomically.
    ///
    /// - Parameters:
    ///   - baseURL: Root URL prepended to all relative paths. Pass `nil` to require absolute URLs.
    ///   - defaultHeaders: Headers added to every request. Pass an empty dictionary for none.
    ///   - timeout: Default request timeout in seconds.
    ///   - loggingEnabled: `YES` to print the structured call log to the console (DEBUG only).
    @objc public func configure(
        baseURL: String?,
        defaultHeaders: [String: String],
        timeout: TimeInterval,
        loggingEnabled: Bool
    ) {
        manager.configure(with: NexNetConfig(
            baseURL: baseURL,
            defaultHeaders: defaultHeaders,
            timeout: timeout,
            isLoggingEnabled: loggingEnabled
        ))
    }

    // MARK: - HTTP Methods

    /// Performs a GET request and delivers the raw response bytes on the main queue.
    ///
    /// - Parameters:
    ///   - url: Absolute URL or relative path resolved against the configured base URL.
    ///   - headers: Optional per-request headers. Pass `nil` to use only the default headers.
    ///   - completion: Called on the main queue with:
    ///     - `data` — raw response bytes (`nil` on error).
    ///     - `statusCode` — HTTP status code, or `0` on non-HTTP errors.
    ///     - `error` — `NSError` with domain `com.nexnet.error` on failure, `nil` on success.
    /// - Returns: A `NexNetCancellable` token that can abort the request.
    @objc @discardableResult
    public func get(
        url: String,
        headers: [String: String]?,
        completion: @escaping (Data?, Int, NSError?) -> Void
    ) -> NexNetCancellable {
        perform(url: url, method: .get, headers: headers, body: nil, completion: completion)
    }

    /// Performs a POST request and delivers the raw response bytes on the main queue.
    ///
    /// - Parameters:
    ///   - url: Absolute URL or relative path.
    ///   - headers: Optional per-request headers.
    ///   - body: Optional pre-encoded JSON body. Use `NSJSONSerialization` to encode dictionaries.
    ///   - completion: Called with raw data, HTTP status code, and any error.
    /// - Returns: A `NexNetCancellable` token.
    @objc @discardableResult
    public func post(
        url: String,
        headers: [String: String]?,
        body: Data?,
        completion: @escaping (Data?, Int, NSError?) -> Void
    ) -> NexNetCancellable {
        perform(url: url, method: .post, headers: headers, body: body, completion: completion)
    }

    /// Performs a PUT request and delivers the raw response bytes on the main queue.
    ///
    /// - Parameters:
    ///   - url: Absolute URL or relative path.
    ///   - headers: Optional per-request headers.
    ///   - body: Optional pre-encoded JSON body.
    ///   - completion: Called with raw data, HTTP status code, and any error.
    /// - Returns: A `NexNetCancellable` token.
    @objc @discardableResult
    public func put(
        url: String,
        headers: [String: String]?,
        body: Data?,
        completion: @escaping (Data?, Int, NSError?) -> Void
    ) -> NexNetCancellable {
        perform(url: url, method: .put, headers: headers, body: body, completion: completion)
    }

    /// Performs a PATCH request and delivers the raw response bytes on the main queue.
    ///
    /// - Parameters:
    ///   - url: Absolute URL or relative path.
    ///   - headers: Optional per-request headers.
    ///   - body: Optional pre-encoded JSON body.
    ///   - completion: Called with raw data, HTTP status code, and any error.
    /// - Returns: A `NexNetCancellable` token.
    @objc @discardableResult
    public func patch(
        url: String,
        headers: [String: String]?,
        body: Data?,
        completion: @escaping (Data?, Int, NSError?) -> Void
    ) -> NexNetCancellable {
        perform(url: url, method: .patch, headers: headers, body: body, completion: completion)
    }

    /// Performs a DELETE request and delivers the raw response bytes on the main queue.
    ///
    /// - Parameters:
    ///   - url: Absolute URL or relative path.
    ///   - headers: Optional per-request headers.
    ///   - completion: Called with raw data (usually empty), HTTP status code, and any error.
    /// - Returns: A `NexNetCancellable` token.
    @objc @discardableResult
    public func delete(
        url: String,
        headers: [String: String]?,
        completion: @escaping (Data?, Int, NSError?) -> Void
    ) -> NexNetCancellable {
        perform(url: url, method: .delete, headers: headers, body: nil, completion: completion)
    }

    // MARK: - Private

    private func perform(
        url: String,
        method: HTTPMethod,
        headers: [String: String]?,
        body: Data?,
        completion: @escaping (Data?, Int, NSError?) -> Void
    ) -> NexNetCancellable {
        let requestBody: RequestBody = body.map { .json($0) } ?? .empty
        return NexNetCancellable(Task {
            do {
                let response = try await manager.rawRequest(
                    urlString: url, method: method,
                    headers: headers, body: requestBody
                )
                DispatchQueue.main.async {
                    completion(response.data, response.statusCode, nil)
                }
            } catch let error as NexNetError {
                DispatchQueue.main.async {
                    completion(nil, error.statusCode ?? 0, error as NSError)
                }
            } catch {
                let nexErr = NexNetError.from(error)
                DispatchQueue.main.async {
                    completion(nil, nexErr.statusCode ?? 0, nexErr as NSError)
                }
            }
        })
    }
}
