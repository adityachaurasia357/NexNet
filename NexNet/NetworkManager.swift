//
//  NetworkManager.swift
//  NexNet
//
//  Created by Aditya Chaurasia on 22/06/2026.
//

import Foundation

// MARK: - NexNetConfig

/// Runtime configuration applied to `NetworkManager.shared` via `configure(with:)`.
///
/// Unlike `NetworkManagerConfiguration` (which is fixed at init), a `NexNetConfig` can be
/// applied or replaced at any time and takes effect for all subsequent requests.
///
/// ```swift
/// NetworkManager.shared.configure(with: NexNetConfig(
///     baseURL: "https://api.example.com",
///     defaultHeaders: ["Authorization": "Bearer token"],
///     timeout: 30,
///     isLoggingEnabled: true
/// ))
/// ```
public struct NexNetConfig: Sendable {
    /// Root URL prepended to every relative path.
    ///
    /// - A path is considered relative when it has no scheme (`http://` / `https://`).
    /// - Both `/users/1` and `users/1` are resolved correctly — the leading slash is
    ///   normalised automatically.
    /// - Absolute URLs passed to `fetch` or `NetworkRequest` are never modified.
    public var baseURL: String?

    /// Headers merged into every request on top of the framework's built-in defaults
    /// (`Accept`, `Accept-Encoding`). Per-request headers override these.
    public var defaultHeaders: [String: String]

    /// Default request timeout in seconds. Applied when a `NetworkRequest` uses its
    /// own default of 30 s; an explicit per-request timeout always takes precedence.
    public var timeout: TimeInterval

    /// Enables or disables the structured network-call log. Mirrors
    /// `NetworkManager.shared.isLoggingEnabled`.
    public var isLoggingEnabled: Bool

    public init(
        baseURL: String? = nil,
        defaultHeaders: [String: String] = [:],
        timeout: TimeInterval = 30,
        isLoggingEnabled: Bool = true
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeout = timeout
        self.isLoggingEnabled = isLoggingEnabled
    }
}

// MARK: - NetworkManagerConfiguration

/// Immutable configuration snapshot passed to `NetworkManager` at init time.
public final class NetworkManagerConfiguration: @unchecked Sendable {
    public let urlSessionConfiguration: URLSessionConfiguration
    public let defaultHeaders: [String: String]
    public let decoder: JSONDecoder
    public let logLevel: LogLevel

    public static let `default` = NetworkManagerConfiguration()

    public init(
        urlSessionConfiguration: URLSessionConfiguration = .default,
        defaultHeaders: [String: String] = [
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate, br"
        ],
        decoder: JSONDecoder = ResponseHandler.makeDecoder(),
        logLevel: LogLevel = .debug
    ) {
        self.urlSessionConfiguration = urlSessionConfiguration
        self.defaultHeaders = defaultHeaders
        self.decoder = decoder
        self.logLevel = logLevel
    }
}

// MARK: - NetworkManager

/// Core networking engine. Thread-safe; all properties are set once at init except
/// `_requestBuilder` and `_config` which are updated atomically by `configure(with:)`.
public final class NetworkManager: @unchecked Sendable {
    public static let shared = NetworkManager()

    // Lock guards _requestBuilder and _config only.
    private let configLock = NSLock()
    private let session: URLSession
    private var _requestBuilder: RequestBuilder   // protected by configLock
    private let responseHandler: ResponseHandler
    private let logger: NexNetLogger
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    /// Framework base headers set at init (Accept, Accept-Encoding, …). Kept so
    /// configure(with:) can merge on top without losing them.
    private let baseHeaders: [String: String]
    private var _config: NexNetConfig?             // protected by configLock

    // MARK: Computed accessors

    private var currentRequestBuilder: RequestBuilder { configLock.withLock { _requestBuilder } }
    private var currentConfig: NexNetConfig? { configLock.withLock { _config } }

    // MARK: - Logging control

    /// Enables or disables network call logging.
    ///
    /// Defaults to `true` in DEBUG builds, `false` in RELEASE builds.
    public var isLoggingEnabled: Bool {
        get { logger.isEnabled }
        set { logger.isEnabled = newValue }
    }

    // MARK: - Init

    /// Creates a `NetworkManager` with the supplied immutable configuration.
    ///
    /// - Parameter configuration: URLSession config, default headers, JSON decoder, and log level.
    ///   Defaults to `NetworkManagerConfiguration.default`, which is suitable for most apps.
    public init(configuration: NetworkManagerConfiguration = .default) {
        self.session = URLSession(configuration: configuration.urlSessionConfiguration)
        self.baseHeaders = configuration.defaultHeaders
        self._requestBuilder = RequestBuilder(defaultHeaders: configuration.defaultHeaders)
        self.responseHandler = ResponseHandler()
        self.decoder = configuration.decoder
        self.encoder = JSONEncoder()
        self.logger = NexNetLogger.shared
        NexNetLogger.shared.minimumLevel = configuration.logLevel
    }

    // MARK: - Runtime Configuration

    /// Applies `config` to all subsequent requests.
    ///
    /// - `config.defaultHeaders` are merged on top of the framework's built-in defaults,
    ///   giving priority to the caller's values. Per-request headers still override everything.
    /// - `config.baseURL` is stored and prepended automatically to any relative URL string.
    /// - `config.timeout` becomes the new default timeout (30 s if not specified).
    /// - `config.isLoggingEnabled` is forwarded to `isLoggingEnabled` immediately.
    ///
    /// Thread-safe; may be called from any thread or Task.
    public func configure(with config: NexNetConfig) {
        // Merge: framework base headers < config headers (config wins on collision).
        let merged = baseHeaders.merging(config.defaultHeaders) { _, configValue in configValue }
        configLock.withLock {
            _config = config
            _requestBuilder = RequestBuilder(defaultHeaders: merged)
        }
        isLoggingEnabled = config.isLoggingEnabled
    }

    // MARK: - Primary API

    /// Fetches a remote resource and decodes it into `T`.
    ///
    /// - Parameters:
    ///   - responseType: The `Decodable` type to decode the response body into.
    ///   - url: Absolute URL **or** relative path (e.g. `"/users/1"`). A relative path
    ///     is automatically combined with `NexNetConfig.baseURL` when configured.
    ///   - headers: Optional per-request headers; merged on top of default headers.
    ///   - body: Optional `Encodable` payload; auto-encoded to JSON.
    ///   - method: HTTP verb to use.
    public func fetch<T: Decodable & Sendable>(
        responseType: T.Type,
        url: String,
        headers: [String: String]?,
        body: (any Encodable)?,
        method: HTTPMethod
    ) async throws -> T {
        // Snapshot config before crossing async boundaries.
        let config = currentConfig
        let resolvedURL = try resolveURL(url, config: config)

        // Encode body synchronously before any async boundary.
        let requestBody: RequestBody
        if let body {
            do {
                requestBody = .json(try encoder.encode(AnyEncodable(body)))
            } catch {
                throw NexNetError.encodingFailed(error)
            }
        } else {
            requestBody = .empty
        }

        let networkRequest = NetworkRequest(
            url: resolvedURL,
            method: method,
            headers: headers ?? [:],
            body: requestBody,
            timeoutInterval: config?.timeout ?? 30.0
        )

        let response: NetworkResponse<T> = try await request(networkRequest, as: T.self)
        return response.value
    }

    // MARK: - Full Request (returns metadata)

    /// Executes `networkRequest`, decodes the body into `T`, and returns full HTTP metadata.
    public func request<T: Decodable & Sendable>(
        _ networkRequest: NetworkRequest,
        as type: T.Type = T.self,
        decoder: JSONDecoder? = nil
    ) async throws -> NetworkResponse<T> {
        let config  = currentConfig
        let builder = currentRequestBuilder
        let adjusted = try applyConfig(to: networkRequest, config: config)

        let callID     = UUID()
        let urlRequest = try builder.build(from: adjusted)
        let handler    = responseHandler
        let dec        = decoder ?? self.decoder
        let session    = self.session
        let log        = logger
        let start      = Date()

        do {
            let (value, statusCode, allHeaders, data) = try await withRetry(policy: adjusted.retryPolicy) {
                let (d, response) = try await session.data(for: urlRequest)
                let http = try handler.validate(response, data: d)
                let value: T = try handler.decode(T.self, from: d, decoder: dec)
                return (value, http.statusCode, http.allHeaderFields, d)
            }
            let duration = Date().timeIntervalSince(start)
            log.logCall(id: callID, request: urlRequest, statusCode: statusCode,
                        responseData: data, error: nil, duration: duration)
            return NetworkResponse(value: value, statusCode: statusCode,
                                   allHeaderFields: allHeaders, data: data, duration: duration)
        } catch {
            let duration = Date().timeIntervalSince(start)
            log.logCall(id: callID, request: urlRequest,
                        statusCode: (error as? NexNetError)?.statusCode,
                        responseData: nil, error: error, duration: duration)
            throw error
        }
    }

    // MARK: - Raw Request

    /// Executes `networkRequest` and returns the response without decoding.
    public func requestRaw(_ networkRequest: NetworkRequest) async throws -> RawNetworkResponse {
        let config   = currentConfig
        let builder  = currentRequestBuilder
        let adjusted = try applyConfig(to: networkRequest, config: config)

        let callID     = UUID()
        let urlRequest = try builder.build(from: adjusted)
        let handler    = responseHandler
        let session    = self.session
        let log        = logger
        let start      = Date()

        do {
            let (statusCode, allHeaders, data) = try await withRetry(policy: adjusted.retryPolicy) {
                let (d, response) = try await session.data(for: urlRequest)
                let http = try handler.validate(response, data: d)
                return (http.statusCode, http.allHeaderFields, d)
            }
            let duration = Date().timeIntervalSince(start)
            log.logCall(id: callID, request: urlRequest, statusCode: statusCode,
                        responseData: data, error: nil, duration: duration)
            return RawNetworkResponse(statusCode: statusCode, allHeaderFields: allHeaders,
                                      data: data, duration: duration)
        } catch {
            let duration = Date().timeIntervalSince(start)
            log.logCall(id: callID, request: urlRequest,
                        statusCode: (error as? NexNetError)?.statusCode,
                        responseData: nil, error: error, duration: duration)
            throw error
        }
    }

    // MARK: - Private helpers

    /// Resolves a URL string against `config.baseURL` when the string has no scheme.
    ///
    /// Absolute URLs (`https://…`) pass through unchanged.
    /// Relative paths (`/users/1` or `users/1`) are joined to the configured base URL.
    private func resolveURL(_ urlString: String, config: NexNetConfig?) throws -> URL {
        if let url = URL(string: urlString), url.scheme != nil {
            return url
        }
        guard let base = config?.baseURL else {
            throw NexNetError.invalidURL(urlString)
        }
        return try joinBaseURL(base, path: urlString)
    }

    /// Resolves a `URL` value against `config.baseURL` when the URL has no scheme.
    private func resolveURL(_ url: URL, config: NexNetConfig?) throws -> URL {
        guard url.scheme == nil else { return url }
        return try resolveURL(url.absoluteString, config: config)
    }

    /// Joins `base` and `path` using simple string concatenation after normalising slashes.
    ///
    /// This avoids RFC 3986's "remove last path segment" behaviour for base URLs without
    /// a trailing slash, giving predictable `https://host/v1` + `/users` → `https://host/v1/users`.
    private func joinBaseURL(_ base: String, path: String) throws -> URL {
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let normPath    = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: trimmedBase + normPath) else {
            throw NexNetError.invalidURL(path)
        }
        return url
    }

    /// Returns a `NetworkRequest` with config adjustments applied:
    /// - URL resolved against `baseURL` if relative.
    /// - Timeout replaced by `config.timeout` when the request still carries the 30 s default.
    private func applyConfig(to req: NetworkRequest, config: NexNetConfig?) throws -> NetworkRequest {
        let url     = try resolveURL(req.url, config: config)
        // Only substitute config timeout when the request is still at the NetworkRequest default.
        let timeout = (config?.timeout != nil && req.timeoutInterval == 30.0)
            ? config!.timeout
            : req.timeoutInterval

        guard url != req.url || timeout != req.timeoutInterval else { return req }

        return NetworkRequest(
            url: url,
            method: req.method,
            headers: req.headers,
            body: req.body,
            queryParameters: req.queryParameters,
            timeoutInterval: timeout,
            retryPolicy: req.retryPolicy,
            cachePolicy: req.cachePolicy
        )
    }

    // Used by NetworkManager+Completion and NexNetObjC — resolves a URL string then delegates
    // to requestRaw, so both completion-handler and @objc callers share the same pipeline.
    func rawRequest(
        urlString: String,
        method: HTTPMethod,
        headers: [String: String]?,
        body: RequestBody
    ) async throws -> RawNetworkResponse {
        let config = currentConfig
        let url    = try resolveURL(urlString, config: config)
        return try await requestRaw(NetworkRequest(
            url: url,
            method: method,
            headers: headers ?? [:],
            body: body
        ))
    }

    private func withRetry<T>(
        policy: RetryPolicy,
        operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                let nexError = NexNetError.from(error)
                attempt += 1
                guard nexError.isRetryable, attempt <= policy.maxAttempts else {
                    throw nexError
                }
                let delay = policy.delay(for: attempt)
                logger.warning("Retrying (\(attempt)/\(policy.maxAttempts)) after \(String(format: "%.1f", delay))s — \(nexError.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
}

// MARK: - AnyEncodable

/// Type-erases any `Encodable` value so it can be passed to `JSONEncoder.encode(_:)`.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ base: any Encodable) {
        self._encode = base.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
